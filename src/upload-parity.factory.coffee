factory = ($http, $q)->
    class CynnyParityUpload

        _file: null
        _fileSize: null

        _signedToken: null
        _uploadToken: null

        _storageUrl: null
        _bucket: null
        _object: null

        _chunkSize: null
        _parityStep: null
        _totalChunks: null

        _chunkIndex: null

        _xorIndex: null
        _xorLength: null

        _chunkArrayBuffer: null
        _tempArrayBuffer: null

        _chunkCrc: null

        constructor: (params={}, index)->
            required = ['signedToken', 'uploadToken', 'storageUrl', 'bucket', 'object', 'totalChunks', 'chunkSize', 'parityStep', 'file', 'fileSize']
            @_processParams(params, required)

            @_xorLength = Math.min((index + 1) * @_parityStep, @_totalChunks - 1)
            @_xorIndex = index * params.parityStep

        _processParams: (params, required)->
            pkeys = Object.keys(params)

            for p in required
                throw new Error("params are missing required property '#{p}'") if pkeys.indexOf(p) == -1
                @["_#{p}"] = params[p]

        upload: ()->
            return @_calculateParity().then(@_uploadForm.bind(@)).then(@_destroy.bind(@))

        _destroy: ()->
            @_file = null

            @_signedToken = null
            @_uploadToken = null

            @_storageUrl = null
            @_bucket = null
            @_object = null

            @_chunkSize = null
            @_parityStep = null
            @_totalChunks = null

            @_chunkIndex = null

            @_xorIndex = null
            @_xorLength = null

            @_chunkArrayBuffer = null
            @_tempArrayBuffer = null

            @_chunkCrc = null

            return true

        _calculateParity: ()->
            return $q (resolve, reject)=>
                criteria = ()=>
                    return @_xorIndex < @_xorLength

                iterator = (cb)=>
                    start = @_chunkSize * @_xorIndex
                    end = Math.min(start + @_chunkSize, @_fileSize)
                    if start < @_fileSize
                        @_readFileChunk(start, end).then(@_parityIteration.bind(@)).then ()=>
                            @_xorIndex += 1
                            cb()
                        .catch (err)=>
                            cb(err)
                    else
                        @_xorIndex += 1
                        cb()

                callback = (err)=>
                    if err
                        reject(err)
                    else
                        resolve()

                async.whilst(criteria, iterator, callback)
                return

        _parityIteration: ()->
            return $q (resolve, reject)=>
                if @_chunkArrayBuffer == null || @_totalChunks == 1
                    @_chunkArrayBuffer = new Uint8Array(@_tempArrayBuffer)
                    return resolve()

                else
                    arr = new Uint8Array(@_tempArrayBuffer)
                    i = 0

                    while i < arr.length
                        @_chunkArrayBuffer[i] ^= arr[i]
                        i += 1

                    arr = null

                    return resolve()

        _readFileChunk: (start, end)->
            return $q (resolve, reject)=>
                reader = new FileReader()

                reader.onerror = (event)=>
                    reject(event)

                reader.onloadend = (event)=>
                    return false unless event.target.readyState == FileReader.DONE
                    @_tempArrayBuffer = event.target.result

                    resolve()

                reader.readAsArrayBuffer(@_file.slice(start, end))
                return

        _uploadForm: ()->
            return $q (resolve, reject)=>
                httpOptions =
                    transformRequest: angular.identity
                    headers:
                        'Content-Type': undefined
                        'x-cyn-signedtoken': @_signedToken
                        'x-cyn-uploadtoken': @_uploadToken

                fd = new FormData()
                fd.append('crc', @_crcAdler32())
                fd.append('chunk', new Blob([@_chunkArrayBuffer], {type: "application/octet-stream", size: @_chunkArrayBuffer.length }))

                url = "#{@_storageUrl}/b/#{@_bucket}/o/#{@_object}/cnk/#{@_chunkIndex}?Parity=1"

                $http.put(url, fd, httpOptions)
                .then ()=>
                    # should not trigger
                    return resolve()
                .catch (err)=>
                    # Should always trigger as response code is 3xx - redirect
                    if 200 <= Number(err.status) < 400 then resolve() else reject(err)

                return

        _crcAdler32: ()->
            a = 0
            b = 0

            for n in @_chunkArrayBuffer
                a = (a + Number(n)) % 65521
                b = (b + a) % 65521

            return ((b << 16) | a) >>> 0

angular.module('cynny').factory('CynnyParityUploader', ['$http', '$q', factory])
