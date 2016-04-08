factory = ($q)->
    class Hash

        _result: null
        _finalized: null

        _file: null
        _chunkSize: null
        _fileSize: null
        _totalChunks: null

        _chunkIndex: null
        _lastProgress: null

        _bytesPassed: null

        _spark: null

        constructor: ()->
            @_spark = new SparkMD5.ArrayBuffer()

            @_finalized = false
            @_bytesPassed = 0


        update: (data)->
            @_bytesPassed += data.byteLength
            @_spark.append(data)
            return @

        digest: ()->
            @_result = @_spark.end()
            @_finalized = true
            @_progressListeners = null

        getResult: ()->
            throw new Error('Not finalized') unless @_finalized
            return @_result

        # @override
        onProgress: (progress)->
            return

        hashFile: (file, chunkSize=65536)->
            @_file = file
            @_fileSize = file.size
            @_chunkSize = chunkSize
            @_totalChunks = Math.ceil(@_fileSize / @_chunkSize)
            @_chunkIndex = 0
            @_lastProgress = 0
            return @_performHashing()

        _performHashing: ()->
            return $q (resolve, reject)=>
                criteria = ()=>
                    return @_chunkIndex < @_totalChunks

                iterator = (cb)=>
                    start = @_chunkIndex * @_chunkSize
                    end = Math.min(start + @_chunkSize, @_fileSize)
                    if start >= @_fileSize
                        @_chunkIndex += 1
                        return cb()

                    @_readFileChunk(start, end).then (arrayBuffer)=>
                        @update(arrayBuffer)
                        @_progress()
                        @_chunkIndex += 1
                        cb()
                    .catch (err)=>
                        err ?= new Error('Ooops, something went wrong')
                        console.log 'error'
                        cb(err)

                    return

                callback = (err)=>
                    if err
                        reject(err)
                    else
                        @digest()
                        resolve(@_result)

                async.whilst(criteria, iterator, callback)
                return

        _readFileChunk: (start, end)->
            return $q (resolve, reject)=>
                reader = new FileReader()

                reader.onloadend = (event)=>
                    return false unless event.target.readyState == FileReader.DONE

                    return resolve(event.target.result)

                reader.onerror = (err)=>
                    return reject(err)

                reader.readAsArrayBuffer(@_file.slice(start, end))
                return

        _progress: ()->
            currentProgress = Math.floor(100 / @_totalChunks * (@_chunkIndex + 1))
            @onProgress(currentProgress) if typeof @onProgress == 'function' && currentProgress != @_lastProgress

            @_lastProgress = currentProgress
            return


angular.module('cynny').factory('MD5', ['$q', factory])
