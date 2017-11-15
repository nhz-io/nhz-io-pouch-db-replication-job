# PouchDB replication job (control)

[![Travis Build][travis]](https://travis-ci.org/nhz-io/nhz-io-pouch-db-replication-job)
[![NPM Version][npm]](https://www.npmjs.com/package/@nhz.io/pouch-db-replication-job)

## Install

```bash
npm i -S @nhz.io/pouch-db-replication-job
```

## Usage
```js
const pouchDbReplicationJob = require('@nhz.io/pouch-db-replication-job')

...
```
## Literate Source

### Imports

    curryN = require 'curry-n'

### Helpers

    keys = (obj) -> Object.keys obj

    assign = (sources...) -> Object.assign {}, sources...

    isString = (maybeString) -> typeof maybeString is 'string'

### Definitions

> Global Job UID

    uid = 0

> Replication defaults

    def = {

      live: false

      retry: false

      since: 0

    }

### Job generator

    pouchDbReplicationJob = (options, source, target, ctx) ->

> Hoist `stop` and `replication` (for Promise below)

      stop = replication = null

> Get pouch from context or global (context comes from queue manager, if any)

      PouchDB = ctx.PouchDB or PouchDB

> Preload databases

      source = new PouchDB source if isString source

      target = new PouchDB target if isString target

> Assign defaults

      options = assign def, options

#### Create and start the job

Job is actually a promise extended with extra properties.

Promise states meaning:

* Promise resolved &rarr; replication has finished (Connection might still be open)
* Promise rejected
  * `err` is empty &rarr; replication was cancelled
  * otherwise, `err` contains the reason and will be set to `job.error`

>

      job = new Promise (resolve, reject) ->

        replication = ctx.PouchDB.replicate source, target, assign options

> Job stopper (`err` is optional - no `err` means manual stop)

        stop = (err) ->

          replication.cancel()

          return if job.done

          job.done = true

          job.error = err or false

          reject job.error

          return job

> Job completer

        complete = (info) ->

          job.info = info if info

          return if job.done

          job.done = true

          job.error = false

          resolve job.replication.state

#### PouchDB replication events

        replication.on 'error', stop

        replication.on 'denied', stop


> Live replications fire `complete` only when cancelled

        replication.on 'complete', complete


> Applies only to `retry` replications

        replication.on 'active', -> job.started = true

        replication.on 'paused', (err) -> if err then stop err else complete()

        replication.then(complete).catch(stop)

> Extend the promise and return

      uid = uid + 1

      Object.assign job, {
        uid, options, stop, source, target, replication
      }

## Exports (Curried)

    module.exports = curryN 4, pouchDbReplicationJob

## Tests

    tape = require 'tape'
    _test = (require 'tape-promise').default
    test = _test(tape)

    PouchDB = require 'pouchdb-memory'

    pouchDbReplicationJob = module.exports

    mkSource = (n = 3) ->

      db = new PouchDB "source-#{ Math.random().toString().slice 2 }"

      await db.put { _id: "doc-#{ i }" } for i in [1..n]

      db

    mkTarget = -> "target-#{ Math.random().toString().slice 2 }"

    test 'job completion', (t) ->

> One-Shot

      source = await mkSource()

      target = mkTarget()

      startJob = pouchDbReplicationJob {}, source, target

      await job = startJob { PouchDB }

      target = job.target

      t.deepEqual (await source.allDocs()), (await target.allDocs()), 'docs match'

      job.stop()

      t.equals job.info.status, 'complete'

> Live

      target = mkTarget()

      startJob = pouchDbReplicationJob { live: true, retry: true }, source, target

      await job = startJob { PouchDB }

      target = job.target

      t.deepEqual (await source.allDocs()), (await target.allDocs()), 'docs match'

      job.stop()

      t.equals job.info.status, 'cancelled'

> Failure

    test 'job fail', (t) ->

      target = mkTarget()

      startJob = pouchDbReplicationJob { live: true, retry: true }, 'http://foo-not-found', target

      try
        await job = startJob { PouchDB }

        t.fail()

      catch err

        t.equals err.status, 500

## Version 1.0.0

## License [MIT](LICENSE)

[travis]: https://img.shields.io/travis/nhz-io/nhz-io-pouch-db-replication-job.svg?style=flat
[npm]: https://img.shields.io/npm/v/@nhz.io/pouch-db-replication-job.svg?style=flat
