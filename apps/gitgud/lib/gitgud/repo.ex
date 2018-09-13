defmodule GitGud.Repo do
  @moduledoc """
  Repository schema and helper functions.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Multi

  alias GitRekt.Git

  alias GitGud.User
  alias GitGud.DB

  schema "repositories" do
    belongs_to    :owner,       User
    field         :name,        :string
    field         :public,      :boolean
    field         :description, :string
    many_to_many  :maintainers, User, join_through: "repositories_maintainers"
    timestamps()
  end

  @type t :: %__MODULE__{
    id: pos_integer,
    owner_id: pos_integer,
    owner: User.t,
    name: binary,
    public: boolean,
    description: binary,
    maintainers: [User.t],
    inserted_at: NaiveDateTime.t,
    updated_at: NaiveDateTime.t,
  }

  @doc """
  Returns `true` if `user` has read access to `repo`; elsewhise returns `false`.
  """
  @spec can_read?(t, User.t) :: boolean
  def can_read?(%__MODULE__{} = _repo, %User{} = _user), do: true
  def can_read?(_repo, nil), do: true

  @doc """
  Returns `true` if `user` has write access to `repo`; elsewhise returns `false`.
  """
  @spec can_write?(t, User.t) :: boolean
  def can_write?(%__MODULE__{owner_id: user_id} = _repo, %User{id: user_id} = _user), do: true
  def can_write?(_repo, _user), do: false

  @doc """
  Returns a repository changeset for the given `params`.
  """
  @spec changeset(t, map) :: Ecto.Changeset.t
  def changeset(%__MODULE__{} = repository, params \\ %{}) do
    repository
    |> cast(params, [:owner_id, :name, :public, :description])
    |> validate_required([:owner_id, :name])
    |> validate_format(:name, ~r/^[a-zA-Z0-9_-]+$/)
    |> validate_length(:name, min: 3, max: 80)
    |> assoc_constraint(:owner)
    |> unique_constraint(:name, name: :repositories_owner_id_name_index)
  end

  @doc """
  Creates a new repository.
  """
  @spec create(map|keyword, keyword) :: {:ok, t, Git.repo} | {:error, Ecto.Changeset.t | term}
  def create(params, opts \\ []) do
    case multi_create(changeset(%__MODULE__{}, Map.new(params)), Keyword.get(opts, :bare, true)) do
      {:ok, %{repo: repo, init: ref}} -> {:ok, repo, ref}
      {:error, :insert, changeset, _changes} -> {:error, changeset}
      {:error, :init, reason, _changes} -> {:error, reason}
      {:error, :put_maintainer, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Similar to `create/2`, but raises an `Ecto.InvalidChangesetError` if an error occurs.
  """
  @spec create!(map|keyword, keyword) :: {t, pid}
  def create!(params, opts \\ []) do
    case create(params, opts) do
      {:ok, repo, pid} -> {repo, pid}
      {:error, changeset} -> raise Ecto.InvalidChangesetError, action: changeset.action, changeset: changeset
    end
  end

  @doc """
  Updates the given `repo` with the given `params`.
  """
  @spec update(t, map|keyword) :: {:ok, t} | {:error, Ecto.Changeset.t | :file.posix}
  def update(%__MODULE__{} = repo, params) do
    changeset = changeset(repo, Map.new(params))
    case multi_update(changeset) do
      {:ok, %{update: repo}} -> {:ok, repo}
      {:error, :update, changeset, _changes} -> {:error, changeset}
      {:error, :rename, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Similar to `update/2`, but raises an `Ecto.InvalidChangesetError` if an error occurs.
  """
  @spec update!(t, map|keyword) :: t
  def update!(%__MODULE__{} = repo, params) do
    case update(repo, params) do
      {:ok, repo} -> repo
      {:error, %Ecto.Changeset{} = changeset} ->
        raise Ecto.InvalidChangesetError, action: changeset.action, changeset: changeset
      {:error, reason} ->
        raise File.Error, reason: reason, action: "rename directory", path: IO.chardata_to_string(workdir(repo))
    end
  end

  @doc """
  Deletes the given `repo`.
  """
  @spec delete(t) :: {:ok, t} | {:error, Ecto.Changeset.t}
  def delete(%__MODULE__{} = repo) do
    case multi_delete(repo) do
      {:ok, %{delete: repo}} -> {:ok, repo}
      {:error, :delete, changeset, _changes} -> {:error, changeset}
      {:error, :cleanup, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Similar to `delete!/1`, but raises an `Ecto.InvalidChangesetError` if an error occurs.
  """
  @spec delete!(t) :: t
  def delete!(%__MODULE__{} = repo) do
    case delete(repo) do
      {:ok, repo} -> repo
      {:error, changeset} -> raise Ecto.InvalidChangesetError, action: changeset.action, changeset: changeset
    end
  end

  @doc """
  Returns the absolute path to the Git workdir for the given `repo`.
  """
  @spec workdir(t) :: Path.t
  def workdir(%__MODULE__{} = repo) do
    root = Application.fetch_env!(:gitgud, :git_dir)
    repo = DB.preload(repo, :owner)
    Path.join([root, repo.owner.username, repo.name])
  end

  @doc """
  Broadcasts notification(s) for the given `service` command.
  """
  @spec notify_command(t, User.t, struct) :: :ok
  def notify_command(%__MODULE__{} = repo, %User{} = user, %GitRekt.WireProtocol.ReceivePack{state: :done, cmds: cmds} = _service) do
    IO.puts "push notification from #{user.username} to #{repo.name}"
    Enum.each(cmds, fn
      {:create, oid, refname} ->
        IO.puts "create #{refname} to #{Git.oid_fmt(oid)}"
      {:update, old_oid, new_oid, refname} ->
        IO.puts "update #{refname} from #{Git.oid_fmt(old_oid)} to #{Git.oid_fmt(new_oid)}"
      {:delete, old_oid, refname} ->
        IO.puts "delete #{refname} (was #{Git.oid_fmt(old_oid)})"
    end)
  end

  def notify_command(%__MODULE__{} = _repo, _user, _service), do: :ok

  #
  # Helpers
  #

  defp multi_create(changeset, bare?) do
    Multi.new()
    |> Multi.insert(:insert, changeset)
    |> Multi.run(:init, &init(&1, bare?))
    |> Multi.merge(&put_maintainer/1)
    |> DB.transaction()
  end

  defp multi_update(changeset) do
    Multi.new()
    |> Multi.update(:update, changeset)
    |> Multi.run(:rename, &rename(&1, changeset.data))
    |> DB.transaction()
  end

  defp multi_delete(repo) do
    Multi.new()
    |> Multi.delete(:delete, repo)
    |> Multi.run(:cleanup, &cleanup/1)
    |> DB.transaction()
  end

  defp init(%{insert: repo}, bare?) do
    Git.repository_init(workdir(repo), bare?)
  end

  def rename(%{update: repo}, old_repo) do
    old_workdir = workdir(old_repo)
    new_workdir = workdir(repo)
    case File.rename(old_workdir, new_workdir) do
      :ok -> {:ok, {old_workdir, new_workdir}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp put_maintainer(%{insert: repo}) do
    Multi.insert_all(Multi.new(), :put_maintainer, "repositories_maintainers", [[repo_id: repo.id, user_id: repo.owner_id]])
  end

  defp cleanup(%{delete: repo}) do
    File.rm_rf(workdir(repo))
  end
end
