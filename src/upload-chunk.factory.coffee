factory = ($http, $q)->
    class CynnyChunkUploader

        _file: null

        _signedToken: null
        _uploadToken: null

        _storageUrl: null
        _bucket: null
        _object: null

        _chunkSize: null
        _chunkIndex: null

        _chunkArrayBuffer: null

        constructor: (params={}, index)->
            required = ['signedToken', 'uploadToken', 'storageUrl', 'bucket', 'object', 'chunkSize', 'file', 'fileSize']
            @_chunkIndex = index
            @_processParams(params, required)

        _processParams: (params, required)->
            pkeys = Object.keys(params)

            for p in required
                throw new Error("params are missing required property '#{p}'") if pkeys.indexOf(p) == -1
                @["_#{p}"] = params[p]

        upload: ()->
            return @_readFileChunk().then(@_uploadForm.bind(@)).then(@_destroy.bind(@))

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

                url = "#{@_storageUrl}/b/#{@_bucket}/o/#{@_object}/cnk/#{@_chunkIndex}"

                $http.put(url, fd, httpOptions)
                .then ()=>
                    # should not trigger
                    return resolve()
                .catch (err)=>
                    # Should always trigger as response code is 3xx - redirect
                    if 200 <= Number(err.status) < 400 then resolve() else reject(err)

                return

        _readFileChunk: ()->
            return $q (resolve, reject)=>
                reader = new FileReader()

                reader.onerror = (event)=>
                    reject(event)

                reader.onloadend = (event)=>
                    return false unless event.target.readyState == FileReader.DONE

                    @_chunkArrayBuffer = event.target.result
                    resolve()

                start = @_chunkIndex * @_chunkSize
                end = Math.min(start + @_chunkSize, @_fileSize)
                reader.readAsArrayBuffer(@_file.slice(start, end))
                return

        _destroy: ()->
            @_file = null

            @_signedToken = null
            @_uploadToken = null

            @_storageUrl = null
            @_bucket = null
            @_object = null

            @_chunkSize = null
            @_chunkIndex = null

            @_chunkArrayBuffer = null
            return true

        _crcAdler32: ()->
            a = 0
            b = 0

            data = new Uint8Array(@_chunkArrayBuffer)

            for n in data
                a = (a + Number(n)) % 65521
                b = (b + a) % 65521

            data = null
            return ((b << 16) | a) >>> 0


angular.module('cynny').factory('CynnyChunkUploader', ['$http', '$q', factory])
