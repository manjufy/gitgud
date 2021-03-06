import {Environment, Network, Store, RecordSource} from "relay-runtime"
import * as AbsintheSocket from "@absinthe/socket"
import {createFetcher, createSubscriber} from "@absinthe/socket-relay/compat/cjs"

import socket from "./socket"

const transport = AbsintheSocket.create(socket)

function fetchQuery(operation, variables) {
  return fetch("/graphql", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: operation.text,
      variables,
    }),
  }).then(response => {
    return response.json()
  })
}

export default new Environment({
  network: Network.create(
    fetchQuery,
    createSubscriber(transport)
  ),
  store: new Store(new RecordSource())
})
