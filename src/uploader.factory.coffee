factory = ($http, $q, MD5, CynnyChunkUploader, CynnyParityUploader)->
    class CynnyUploader

        # Constructor Parametets => Required
        _storageUrl: null
        _bucket: null
        _object: null
        _signedToken: null

        _file: null

        # Calculated Values
        _fileSize: null
        _fileMd5: null

        # Values Retrieved Upon Object Creation
        _uploadToken: null
        _totalChunks: null
        _partityChunks: null
        _parityStep: null
        _chunkSize: null

        # Progress Tracking
        _uploadQueue: null
        _uploadedChunks: null
        _lastProgress: null

        constructor: (params={}, concurrency=1)->
            required = ['signedToken', 'storageUrl', 'bucket', 'object', 'file']
            @_processParams(params, required)
            @_fileSize = @_file.size


        _processParams: (params, required)->
            pkeys = Object.keys(params)

            for p in required
                throw new Error("params are missing required property '#{p}'") if pkeys.indexOf(p) == -1
                @["_#{p}"] = params[p]

        # @OVERRIDE - optional
        onPreparetionProgress: (prog)->
            return

        # @OVERRIDE - optional
        onUploadProgress: (prog)->
            return

        upload: ()->
            @_uploadQueue = []
            @_uploadedChunks = 0

            return @_getFileHash().then(@_createFile.bind(@)).then(@_createUploadQueue.bind(@)).then(@_processUploadQueue.bind(@)).then(@_finalizeFile.bind(@))

        _progress: ()-> # TODO: Modify
            currentProgress = Math.floor(@_uploadedChunks / (@_totalChunks + @_partityChunks) * 100)
            @onUploadProgress(currentProgress) if typeof @onUploadProgress == 'function' && currentProgress != @_lastProgress

            @_lastProgress = currentProgress
            return

        _getFileHash: ()->
            return $q (resolve, reject)=>

                hash = new MD5()

                hash.onProgress = (progress)=>
                    @onPreparetionProgress(progress)

                hash.hashFile(@_file).then (checksum)=>
                    @_fileMd5= checksum
                    resolve()
                .catch(reject)
                return

        _createFile: ()->
            data =
                md5Encode: @_fileMd5
                name: @_object
                size: @_fileSize

            httpOptions =
                headers:
                    'Content-Type': 'application/json'
                    'x-cyn-signedtoken': @_signedToken

            return $http.post("#{@_storageUrl}/b/#{@_bucket}/o", data, httpOptions).then (response)=>
                @_uploadToken = response.data.data.uploadToken
                @_totalChunks = response.data.data.emptyChunks
                @_partityChunks = response.data.data.emptyChunksParity
                @_parityStep = response.data.data.object.parityStep
                @_chunkSize = response.data.data.object.chunkSize

                return true

        _createUploadQueue: ()->
            @_createChunks()
            @_createParity()
            return true

        _createChunks: ()->
            c = 0
            chunkParams =
                storageUrl: @_storageUrl
                file: @_file
                fileSize: @_fileSize
                uploadToken: @_uploadToken
                signedToken: @_signedToken
                bucket: @_bucket
                object: @_object
                chunkSize: @_chunkSize

            while c < @_totalChunks
                @_uploadQueue.push(new CynnyChunkUploader(chunkParams, c))
                c += 1
            return true

        _createParity: ()->
            p = 0
            chunkParams =
                storageUrl: @_storageUrl
                file: @_file
                fileSize: @_fileSize
                uploadToken: @_uploadToken
                signedToken: @_signedToken
                chunkSize: @_chunkSize
                bucket: @_bucket
                object: @_object

                parityStep: @_parityStep
                totalChunks: @_totalChunks
            while p < @_partityChunks
                @_uploadQueue.push(new CynnyParityUploader(chunkParams, p))
                p += 1
            return true

        _processUploadQueue: ()->
            return new Promise (resolve, reject)=>
                criteria = ()=>
                    return @_uploadQueue.length > 0

                iterator = (cb)=>
                    upItem = @_uploadQueue.shift()
                    prom = upItem.upload()

                    prom.then ()=>
                        upItem = null
                        prom = null
                        @_uploadedChunks += 1
                        @_progress()
                        cb()
                    prom.catch (err)=>
                        # TODO: Implement retries in the future
                        err ?= new Error("Chunk #{upItem._chunkIndex} failed to upload")
                        upItem = null
                        prom = null
                        cb(err)

                callback = (err)=>
                    reject(err) if err
                    resolve()

                async.whilst(criteria, iterator, callback)
                return

        _finalizeFile: ()->
                httpOptions =
                    headers:
                        'Content-Type': 'application/json'
                        'x-cyn-signedtoken': @_signedToken
                        'x-cyn-uploadtoken': @_uploadToken

                return $http.patch("#{@_storageUrl}/b/#{@_bucket}/o/#{@_object}", {status: 1}, httpOptions)

angular.module('cynny').factory('CynnyUploader', ['$http', '$q', 'MD5', 'CynnyChunkUploader', 'CynnyParityUploader', factory])
