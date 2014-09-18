sdch = require '../lib/sdch'
chai = require 'chai'
crypto = require 'crypto'
stream = require 'stream'
url = require 'url'

should = chai.should()

describe 'sdch', ->
  class BufferingStream extends stream.Writable
    constructor: (finishcb) ->
      super()
      @nread = 0
      @data_ = []
      @on 'finish', ->
        finishcb(Buffer.concat(@data_, @nread))

    _write: (chunk, encoding, next) ->
      chunk.should.be.instanceof Buffer
      @nread += chunk.length
      @data_.push(chunk)
      next()

  it 'should have all expected exports', ->
    sdch.should.respondTo 'SdchEncoder'
    sdch.should.respondTo 'SdchDecoder'
    sdch.should.respondTo 'SdchDictionary'
    sdch.should.respondTo 'createSdchEncoder'
    sdch.should.respondTo 'createSdchDecoder'
    sdch.should.respondTo 'sdchEncode'
    sdch.should.respondTo 'sdchEncodeSync'
    sdch.should.respondTo 'sdchDecode'
    sdch.should.respondTo 'sdchDecodeSync'
    sdch.should.respondTo 'createSdchDictionary'
    sdch.should.have.property 'clientUtils'
    sdch.clientUtils.should.respondTo 'canSetDictionary'
    sdch.clientUtils.should.respondTo 'canUseDictionary'
    sdch.clientUtils.should.respondTo 'canAdvertiseDictionary'
    sdch.clientUtils.should.respondTo 'canFetchDictionary'
    sdch.clientUtils.should.respondTo 'pathMatch'
    sdch.clientUtils.should.respondTo 'domainMatch'

  describe 'SdchDictionary', ->
    it 'should throw if no url string provided', ->
      (-> new sdch.SdchDictionary data: '12345')
      .should.throw /url must be string/

      (-> new sdch.SdchDictionary url: 123)
      .should.throw /url must be string/

    it 'should throw if no domain string provided', ->
      (-> new sdch.SdchDictionary url: '12345')
      .should.throw /domain must be string/

      (-> new sdch.SdchDictionary url: '12345', domain: 123)
      .should.throw /domain must be string/

    it 'should throw if no data string/Buffer provided', ->
      (-> new sdch.SdchDictionary url: '12345', domain: 'kotiki.cc')
      .should.throw /dictionary without data/

      (-> new sdch.SdchDictionary url: '12345', domain: 'kotiki.cc', data: 123)
      .should.throw /data must be Buffer or string/

    it 'should be created with url, domain and data provided', ->
      (-> new sdch.SdchDictionary
        url: '12345'
        domain: 'kotiki.cc'
        data: 'kotiki'
      ).should.not.throw()

    it 'should throw if path is not string', ->
      (-> new sdch.SdchDictionary
        url: '12345'
        domain: 'kotiki.cc'
        data: 'kotiki'
        path: 123
      ).should.throw /path must be string/

    it 'should throw if format-version is not string', ->
      (-> new sdch.SdchDictionary
        url: '12345'
        domain: 'kotiki.cc'
        data: 'kotiki'
        formatVersion: 123
      ).should.throw /formatVersion must be string/

    it 'should throw if max-age is not integer', ->
      (-> new sdch.SdchDictionary
        url: '12345'
        domain: 'kotiki.cc'
        data: 'kotiki'
        maxAge: '.43'
      ).should.throw /maxAge must be integer/

      (-> new sdch.SdchDictionary
        url: '12345'
        domain: 'kotiki.cc'
        data: 'kotiki'
        maxAge: 'ad'
      ).should.throw /maxAge must be integer/

    it 'should throw if ports is not array of ints', ->
      (-> new sdch.SdchDictionary
        url: '12345'
        domain: 'kotiki.cc'
        data: 'kotiki'
        ports: ['asdas']
      ).should.throw /ports must be array of integers/

      (-> new sdch.SdchDictionary
        url: '12345'
        domain: 'kotiki.cc'
        data: 'kotiki'
        ports: [1, 123, 'asdas']
      ).should.throw /ports must be array of integers/

      (-> new sdch.SdchDictionary
        url: '12345'
        domain: 'kotiki.cc'
        data: 'kotiki'
        ports: 'ad'
      ).should.throw /ports must be array of integers/

    headerString = 'domain: kotiki.cc\npath: /path\nformat-version: 1.0\n' +
        'max-age: 3000\nport: 80\nport: 443\n\n'
    testData = 'котики'
    testOpts =
      url: 'kotiki.cc/dict'
      domain: 'kotiki.cc'
      path: '/path'
      data: testData
      formatVersion: '1.0'
      maxAge: 3000
      ports: [80, 443]

    it 'should be created with correct params', ->
      dict = new sdch.SdchDictionary testOpts

      dict.url.should.equal 'kotiki.cc/dict'
      dict.domain.should.equal 'kotiki.cc'
      dict.path.should.equal '/path'
      dict.data.toString().should.equal testData
      dict.formatVersion.should.equal '1.0'
      dict.maxAge.should.equal 3000
      # TODO: I'm too stupid to hanle nodejs Dates
      # offset = new Date().getTimezoneOffset() / 60
      # now = new Date()
      # now.setSeconds now.getSeconds() + 3000
      # new Date(dict.expiration.getTime() - offset).should.be.at.least now
      dict.ports.should.eql [80, 443]
      shasum = crypto.createHash 'sha256'
      shasum.update new Buffer headerString
      shasum.update new Buffer testData
      hash = shasum.digest();
      urlSafe = (str) ->
        str.replace(/\+/g, '-').replace(/\//g, '_').replace(/\=+$/, '')
      etag = urlSafe(hash.slice(0, 16).toString('base64'))
      clientHash = urlSafe(hash.slice(0, 6).toString('base64'));
      serverHash = urlSafe(hash.slice(6, 12).toString('base64'));
      dict._headersBuffer.toString().should.equal headerString
      dict.clientHash.should.equal clientHash
      dict.serverHash.should.equal serverHash
      dict.getLength().should.equal headerString.length + dict.data.length

    describe 'streaming', ->
      it 'should work', (done) ->
        dict = new sdch.SdchDictionary testOpts
        dict.getOutputStream().pipe new BufferingStream (data) ->
          data.toString().should.equal headerString + testData
          done()

      describe 'ranges', ->
        it 'should work for header only range', (done) ->
          dict = new sdch.SdchDictionary testOpts
          dict.getOutputStream range: { start: 0, end: 10}
          .pipe new BufferingStream (data) ->
            data.toString().should.equal 'domain: ko'
            done()

        it 'should work for body only range', (done) ->
          dict = new sdch.SdchDictionary testOpts
          dict.getOutputStream
            range: { start: headerString.length, end: headerString.length + 6 }
          .pipe new BufferingStream (data) ->
            data.toString().should.equal 'кот'
            done()

        it 'should work for mixed ranges', (done) ->
          dict = new sdch.SdchDictionary testOpts
          dict.getOutputStream
            range: { start: headerString.length - 6, end: headerString.length + 6 }
          .pipe new BufferingStream (data) ->
            data.toString().should.equal ' 443\n\nкот'
            done()

      describe 'parsing', ->
        it 'should throw if no double LF', ->
          testDict = 'domain:kotiki.cc\npath:/\nкотики'
          (-> sdch.createSdchDictionary '/dict', testDict)
          .should.throw /SDCH dictionary headers not found/

        it 'should throw if headers are not splittable by :', ->
          testDict = 'domain-kotiki.cc\npath:/\n\nкотики'
          (-> sdch.createSdchDictionary '/dict', testDict)
          .should.throw /Invalid header string/

        it 'should trim as chromium', ->
          testDict = '  domain:kotiki.cc\npath:  /\n\nкотики'
          # Spaces from the start were not trimmed.
          (-> sdch.createSdchDictionary '/dict', testDict)
          .should.throw /domain must be string/

          testDict = 'domain:kotiki.cc\npath:\t \t/\n\nкотики'
          # Spaces after 'path:' were trimmed
          dict = sdch.createSdchDictionary '/dict', testDict
          dict.path.should.equal '/'

          testDict = 'domain:kotiki.cc\npath:\t \t/  \n  max-age:30\n\nкотики'
          # Spaces after '/' were not trimmed
          dict = sdch.createSdchDictionary '/dict', testDict
          dict.path.should.equal '/  '
          should.not.exist dict.maxAge

  describe 'clientUtils', ->
    cu = sdch.clientUtils
    createDict = -> new sdch.SdchDictionary
      domain: 'kotiki.cc'
      url: 'http://kotiki.cc/dict'
      data: 'котики'

    describe 'domainMatch', ->
      it 'should not allow empty', ->
        t = url.parse '/path'
        cu.domainMatch(t, 'kotiki.cc').should.be.false
        cu.domainMatch(t, '').should.be.false
        cu.domainMatch(url.parse 'http://kotiki.cc', '').should.be.false

      it 'should not allow different domains', ->
        t = url.parse 'http://kotiki.cc'
        cu.domainMatch(t, 'tiki.cc').should.be.false
        cu.domainMatch(t, 'google.com').should.be.false

      it 'should allow exact', ->
        t = url.parse 'http://kotiki.cc'
        cu.domainMatch(t, 'kotiki.cc').should.be.true

      it 'should allow subdomain', ->
        t = url.parse 'http://my.kotiki.cc'
        cu.domainMatch(t, 'kotiki.cc').should.be.true

        t = url.parse 'http://my.best.kotiki.cc'
        cu.domainMatch(t, 'kotiki.cc').should.be.true

        t = url.parse 'http://my.best.kotiki.cc'
        cu.domainMatch(t, 'best.kotiki.cc').should.be.true

      it 'should not allow just substrings', ->
        t = url.parse 'http://mykotiki.cc'
        cu.domainMatch(t, 'kotiki.cc').should.be.false

        t = url.parse 'http://myvery.best.kotiki.cc'
        cu.domainMatch(t, 'very.best.kotiki.cc').should.be.false

    describe 'pathMatch', ->
      it 'should not accept empty stuff', ->
        cu.pathMatch('', '').should.be.false
        cu.pathMatch('/', '').should.be.false
        cu.pathMatch('', '/').should.be.false
        cu.pathMatch(null, '/').should.be.false
        cu.pathMatch('/null', null).should.be.false

      it 'should accept equal paths', ->
        cu.pathMatch('/', '/').should.be.true
        cu.pathMatch('/kotiki', '/kotiki').should.be.true

      it 'should not accept if prefix is longer', ->
        cu.pathMatch('/kotiki', '/kotiki.1').should.be.false

      it 'should not accept if path is not prefix of restriction', ->
        cu.pathMatch('/ktikiki1', '/kotiki').should.be.false

      it 'should not accept if simple substring', ->
        cu.pathMatch('/kotiki1', '/kotiki').should.be.false

      it 'should accept sub-segments', ->
        cu.pathMatch('/kotiki/123', '/kotiki/').should.be.true
        cu.pathMatch('/kotiki/123/45', '/kotiki/').should.be.true
        cu.pathMatch('/kotiki/123/45', '/').should.be.true


    describe 'canSetDictionary', ->
      it 'should not allow empty domains', ->
        cu.canSetDictionary('').should.be.false

      it 'should not allow TLDs', ->
        cu.canSetDictionary('com').should.be.false
        cu.canSetDictionary('com.').should.be.false
        cu.canSetDictionary('co.uk').should.be.false
        cu.canSetDictionary('s3.amazonaws.com').should.be.false

      it 'should allow only same domain', ->
        cu.canSetDictionary(
          'kotiki.cc', '', [], 'http://google.com/dict').should.be.false
        cu.canSetDictionary(
          'my.kotiki.cc', '', [], 'http://kotiki.cc/dict').should.be.false
        cu.canSetDictionary(
          'kotiki.cc', '', [], 'http://kotiki.cc/dict').should.be.true
        cu.canSetDictionary(
          '.kotiki.cc', '', [], 'http://my.kotiki.cc/dict').should.be.true

      it 'should allow only specified ports', ->
        cu.canSetDictionary(
          'kotiki.cc', '', [80], 'http://kotiki.cc/dict').should.be.true
        cu.canSetDictionary(
          'kotiki.cc', '', [80], 'http://kotiki.cc:80/dict').should.be.true
        cu.canSetDictionary(
          'kotiki.cc', '', [80, 443], 'http://kotiki.cc:80/dict')
        .should.be.true
        cu.canSetDictionary(
          'kotiki.cc', '', [443], 'https://kotiki.cc/dict').should.be.true
        cu.canSetDictionary(
          'kotiki.cc', '', [443], 'https://kotiki.cc:80/dict').should.be.false
        cu.canSetDictionary(
          'kotiki.cc', '', [443, 3000], 'https://kotiki.cc:3000/dict')
        .should.be.true

      describe 'canUseDictionary', ->
        it 'should allow only matching domains', ->
          dict = createDict()
          cu.canUseDictionary(dict, 'http://google.com').should.be.false
          cu.canUseDictionary(dict, 'http://kotiki.cc').should.be.true

        it 'should allow only matching ports', ->
          dict = createDict()
          dict.ports = [80, 3000]
          cu.canUseDictionary(dict, 'http://kotiki.cc:443').should.be.false
          cu.canUseDictionary(dict, 'http://kotiki.cc').should.be.true
          cu.canUseDictionary(dict, 'http://kotiki.cc:3000').should.be.true

        it 'should allow any path if dictionary does not specify it', ->
          dict = createDict()
          cu.canUseDictionary(dict, 'http://kotiki.cc/test').should.be.true
          cu.canUseDictionary(dict, 'http://kotiki.cc/').should.be.true
          cu.canUseDictionary(dict, 'http://kotiki.cc/test/123').should.be.true

        it 'should allow only matching paths if specified', ->
          dict = createDict()
          dict.path = '/test/'
          cu.canUseDictionary(dict, 'http://kotiki.cc/test/123').should.be.true
          cu.canUseDictionary(dict, 'http://kotiki.cc/123').should.be.false
          cu.canUseDictionary(dict, 'http://kotiki.cc').should.be.false


        it 'should not allow different protocols', ->
          dict = createDict()
          cu.canUseDictionary(dict, 'https://kotiki.cc').should.be.false
          cu.canUseDictionary(dict, 'http://kotiki.cc').should.be.true
          dict.url = 'https://kotiki.cc/dict'
          cu.canUseDictionary(dict, 'https://kotiki.cc').should.be.true
          cu.canUseDictionary(dict, 'http://kotiki.cc').should.be.false

      describe 'canAdvertiseDictionary', ->
        it 'should allow only matching domains', ->
          dict = createDict()
          cu.canAdvertiseDictionary(dict, 'http://google.com').should.be.false
          cu.canAdvertiseDictionary(dict, 'http://kotiki.cc').should.be.true

        it 'should allow only matching ports', ->
          dict = createDict()
          dict.ports = [80, 3000]
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc:443').should.be.false
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc').should.be.true
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc:3000').should.be.true

        it 'should allow any path if dictionary does not specify it', ->
          dict = createDict()
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc/test').should.be.true
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc/').should.be.true
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc/test/123').should.be.true

        it 'should allow only matching paths if specified', ->
          dict = createDict()
          dict.path = '/test/'
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc/test/123').should.be.true
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc/123').should.be.false
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc').should.be.false

        it 'should not allow different protocols', ->
          dict = createDict()
          cu.canAdvertiseDictionary(
            dict, 'https://kotiki.cc').should.be.false
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc').should.be.true
          dict.url = 'https://kotiki.cc/dict'
          cu.canAdvertiseDictionary(
            dict, 'https://kotiki.cc').should.be.true
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc').should.be.false

        it 'should not allow expired dicts', ->
          dict = createDict()
          now = new Date()
          now.setSeconds(now.getSeconds() - 1000)
          dict.expiration = now
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc').should.be.false

        it 'should allow non-expired dicts', ->
          dict = createDict()
          now = new Date()
          now.setSeconds(now.getSeconds() + 1000)
          dict.expiration = now
          cu.canAdvertiseDictionary(
            dict, 'http://kotiki.cc').should.be.true

      describe 'canFetchDictionary', ->
        it 'should not allow different protocols', ->
          cu.canFetchDictionary(
            'http://kotiki.cc/dict', 'https://kotiki.cc/page').should.be.false
          cu.canFetchDictionary(
            'https://kotiki.cc/dict', 'http://kotiki.cc/page').should.be.false

          cu.canFetchDictionary(
            'http://kotiki.cc/dict', 'http://kotiki.cc/page').should.be.true
          cu.canFetchDictionary(
            'https://kotiki.cc/dict', 'https://kotiki.cc/page').should.be.true

        it 'should not allow different hosts', ->
          cu.canFetchDictionary(
            'http://kotiki.cc/dict', 'https://google.com/page').should.be.false
          cu.canFetchDictionary(
            'http://kotiki.cc/dict', 'http://kotiki.cc/page').should.be.true

  describe 'Encoding/Decoding', ->
    dict = new sdch.SdchDictionary
      url: 'http://kotiki.cc/dict'
      domain: 'kotiki.cc'
      data: new Buffer 'this is a test dictionary not very long'
    testData = 'this is a test dictionary not very long a test dictionary not'

    describe 'SdchEncoder', ->
      it 'should append dict server hash', (done) ->
        out = sdch.sdchEncodeSync testData, dict
        out.toString().slice(0, 9).should.equal dict.serverHash + '\0'

        sdch.sdchEncode testData, dict, (err, enc) ->
          enc.toString().slice(0, 9).should.equal dict.serverHash + '\0'
          done()

    describe 'SdchDecoder', ->
      describe 'decode sync', ->
        it 'should throw if data is too short', ->
          wrongDictData = 'Short'
          (->sdch.sdchDecodeSync wrongDictData, [dict])
          .should.throw /data should at least contain/

        it 'should throw if first 9 bytes are not valid', ->
          wrongDictData = 'NoSuchHashHash\0datadatadata'
          (->sdch.sdchDecodeSync wrongDictData, [dict])
          .should.throw /Invalid server hash/

        it 'should throw if no dict available', ->
          wrongDictData = 'NoSuchHa\0datadatadata'
          (->sdch.sdchDecodeSync wrongDictData, [dict])
          .should.throw /Unknown dictionary/

      describe 'decode async', ->
        # TODO
        xit 'should throw if data is too short', (done) ->
          wrongDictData = 'Short'
          sdch.sdchDecode wrongDictData, [dict], (err, data) ->
            err.message.should.have.string 'data should at least contain'
            done()

        it 'should throw if first 9 bytes are not valid', (done) ->
          wrongDictData = 'NoSuchHashHash\0datadatadata'
          sdch.sdchDecode wrongDictData, [dict], (err, data) ->
            err.message.should.have.string 'Invalid server hash'
            done()

        it 'should throw if no dict available', (done) ->
          wrongDictData = 'NoSuchHa\0datadatadata'
          sdch.sdchDecode wrongDictData, [dict], (err, data) ->
            err.message.should.have.string 'Unknown dictionary'
            done()

    describe 'there and back again', ->
      it 'should encode and decode sync', ->
        e = sdch.sdchEncodeSync testData, dict
        e = sdch.sdchDecodeSync e, [dict]
        e.toString().should.equal testData

      it 'should encode and decode async', (done) ->
        sdch.sdchEncode testData, dict, (err, enc) ->
          sdch.sdchDecode enc, [dict], (err, dec) ->
            dec.toString().should.equal testData
            done()

      it 'should work with stream api', (done) ->
        encoder = sdch.createSdchEncoder dict
        decoder = sdch.createSdchDecoder [dict]

        class ReadingStuff extends stream.Readable
          constructor: (@data) ->
            super()

          _read: () ->
            @push @data
            @data = null

        testIn = new ReadingStuff testData
        testOut = new BufferingStream (result) ->
          result.should.have.length.below testData.length
          encodedIn = new ReadingStuff(result)
          decodedOut = new BufferingStream (result) ->
            result.toString().should.equal testData
            done()
          encodedIn.pipe(decoder).pipe(decodedOut)
        testIn.pipe(encoder).pipe(testOut)
