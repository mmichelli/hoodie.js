describe "Hoodie.Remote", ->  
  beforeEach ->
    @hoodie = new Mocks.Hoodie 
    @remote = new Hoodie.RemoteStore @hoodie
    spyOn(@hoodie, "on")
    spyOn(@hoodie, "one")
    spyOn(@hoodie, "unbind")
    @requestDefer = @hoodie.defer()
    spyOn(@hoodie, "request").andReturn @requestDefer.promise()
    spyOn(window, "setTimeout")
    
    spyOn(@hoodie, "trigger")
    spyOn(@hoodie.my.localStore, "destroy").andReturn then: (cb) -> cb('objectFromStore')
    spyOn(@hoodie.my.localStore, "update").andReturn  then: (cb) -> cb('objectFromStore', false)
  
  
  describe ".constructor(@hoodie, options = {})", ->
    beforeEach ->
      spyOn(Hoodie.RemoteStore::, "connect")
      @remote = new Hoodie.RemoteStore @hoodie
    
    it "should be active by default", ->
      expect(@remote.active).toBeTruthy()
    
    it "should connect", ->
      expect(Hoodie.RemoteStore::connect).wasCalled()
        
    _when "config remote.active is false", ->
      beforeEach ->
        spyOn(@hoodie.my.config, "get").andReturn false
        @remote = new Hoodie.RemoteStore @hoodie
        
      it "should set active to false", ->
        expect(@remote.active).toBeFalsy()
     

  describe ".activate", ->
    it "should set remote.active to true", ->
      @remote.active = false
      @remote.activate()
      expect(@remote.active).toBeTruthy()
    
    it "should set config remote.active to true", ->
      spyOn(@hoodie.my.config, "set")
      @remote.activate()
      expect(@hoodie.my.config.set).wasCalledWith '_remote.active', true

    it "should subscribe to `signedOut` event", ->
      @remote.activate()
      expect(@hoodie.on).wasCalledWith 'account:signedOut', @remote.disconnect

    it "should subscribe to account:signin with sync", ->
      @remote.activate()
      expect(@hoodie.on).wasCalledWith 'account:signedIn', @remote.connect
      
  describe ".deactivate", ->
    it "should set remote.active to false", ->
      @remote.active = true
      @remote.deactivate()
      expect(@remote.active).toBeFalsy()
    
    it "should set config remote.active to false", ->
      spyOn(@hoodie.my.config, "set")
      @remote.deactivate()
      expect(@hoodie.my.config.set).wasCalledWith '_remote.active', false

    it "should unsubscribe from account's signedIn idle event", ->
      @remote.deactivate()
      expect(@hoodie.unbind).wasCalledWith 'account:signedIn', @remote.connect
      
    it "should unsubscribe from account's signedOut idle event", ->
      @remote.deactivate()
      expect(@hoodie.unbind).wasCalledWith 'account:signedOut', @remote.disconnect

  describe ".connect()", ->
    beforeEach ->
      spyOn(@remote, "sync")
      
    it "should authenticate", ->
      spyOn(@hoodie.my.account, "authenticate").andCallThrough()
      @remote.connect()
      expect(@hoodie.my.account.authenticate).wasCalled()
      
    _when "successful", ->
      beforeEach ->
        spyOn(@hoodie.my.account, "authenticate").andReturn pipe: (cb) -> 
          cb()
          fail: ->
        
      it "should sync", ->
        @remote.connect()
        expect(@remote.sync).wasCalled()
  # /.connect()

  describe ".disconnect()", ->  
    it "should abort the pull request", ->
      @remote._pullRequest = abort: jasmine.createSpy 'pull'
      @remote.disconnect()
      expect(@remote._pullRequest.abort).wasCalled()
    
    it "should abort the push request", ->
      @remote._pushRequest = abort: jasmine.createSpy 'push'
      @remote.disconnect()
      expect(@remote._pushRequest.abort).wasCalled()
      
    it "should unsubscribe from stores's dirty idle event", ->
      @remote.disconnect()
      expect(@hoodie.unbind).wasCalledWith 'store:dirty:idle', @remote.push
  # /.disconnect()
  
  describe ".pull()", ->        
    _when "remote is active", ->
      beforeEach ->
        @remote.active = true
      
      it "should send a longpoll GET request to user's db _changes feed", ->
        spyOn(@hoodie.my.account, "db").andReturn 'joe$examleCom'
        @remote.pull()
        expect(@hoodie.request).wasCalled()
        [method, path] = @hoodie.request.mostRecentCall.args
        expect(method).toBe 'GET'
        expect(path).toBe '/joe%24examleCom/_changes?includeDocs=true&heartbeat=10000&feed=longpoll&since=0'
        
      it "should set a timeout to restart the pull request", ->
        @remote.pull()
        expect(window.setTimeout).wasCalledWith @remote._restartPullRequest, 25000
        
    _when "remote is not active", ->
      beforeEach ->
        @remote.active = false
      
      it "should send a normal GET request to user's db _changes feed", ->
        spyOn(@hoodie.my.account, "db").andReturn 'joe$examleCom'
        @remote.pull()
        expect(@hoodie.request).wasCalled()
        [method, path] = @hoodie.request.mostRecentCall.args
        expect(method).toBe 'GET'
        expect(path).toBe '/joe%24examleCom/_changes?includeDocs=true&since=0'

    _when "request is successful / returns changes", ->
      beforeEach ->
        @hoodie.request.andReturn then: (success) =>
          # avoid recursion
          @hoodie.request.andReturn then: ->
          success Mocks.changesResponse()
      
      it "should remove `todo/abc3` from store", ->
        @remote.pull()
        expect(@hoodie.my.localStore.destroy).wasCalledWith 'todo', 'abc3', remote: true

      it "should save `todo/abc2` in store", ->
        @remote.pull()
        expect(@hoodie.my.localStore.update).wasCalledWith 'todo', 'abc2', { _rev : '1-123', content : 'remember the milk', done : false, order : 1, type : 'todo', id : 'abc2' }, { remote : true }
      
      it "should trigger remote events", ->
        @remote.pull()

        # {"_id":"todo/abc3","_rev":"2-123","_deleted":true}
        expect(@hoodie.trigger).wasCalledWith 'remote:destroy',           'objectFromStore'
        expect(@hoodie.trigger).wasCalledWith 'remote:destroy:todo',      'objectFromStore'
        expect(@hoodie.trigger).wasCalledWith 'remote:destroy:todo:abc3', 'objectFromStore'

        expect(@hoodie.trigger).wasCalledWith 'remote:change',            'destroy', 'objectFromStore'
        expect(@hoodie.trigger).wasCalledWith 'remote:change:todo',       'destroy', 'objectFromStore'
        expect(@hoodie.trigger).wasCalledWith 'remote:change:todo:abc3',  'destroy', 'objectFromStore'        
        
        # {"_id":"todo/abc2","_rev":"1-123","content":"remember the milk","done":false,"order":1, "type":"todo"}
        expect(@hoodie.trigger).wasCalledWith 'remote:update',            'objectFromStore'
        expect(@hoodie.trigger).wasCalledWith 'remote:update:todo',       'objectFromStore'
        expect(@hoodie.trigger).wasCalledWith 'remote:update:todo:abc2',  'objectFromStore'

        expect(@hoodie.trigger).wasCalledWith 'remote:change',            'update', 'objectFromStore'
        expect(@hoodie.trigger).wasCalledWith 'remote:change:todo',       'update', 'objectFromStore'
        expect(@hoodie.trigger).wasCalledWith 'remote:change:todo:abc2',  'update', 'objectFromStore'
        
      _and "remote is active", ->
        beforeEach ->
          @remote.active = true
          spyOn(@remote, "pull").andCallThrough()
        
        it "should pull again", ->
          @remote.pull()
          expect(@remote.pull.callCount).toBe 2
        
    _when "request errors with 403 unauthorzied", ->
      beforeEach ->
        @hoodie.request.andReturn then: (success, error) =>
          # avoid recursion
          @hoodie.request.andReturn then: ->
          error status: 403, 'error object'
          
        spyOn(@remote, "disconnect")
      
      it "should disconnect", ->
        @remote.pull()
        expect(@remote.disconnect).wasCalled()
        
      it "should trigger an unauthenticated error", ->
        @remote.pull()
        expect(@hoodie.trigger).wasCalledWith 'remote:error:unauthenticated', 'error object'
      
      _and "remote is active", ->
        beforeEach ->
          @remote.active = true
      
      _and "remote isn't active", ->
        beforeEach ->
          @remote.active = false

    _when "request errors with 404 not found", ->
      beforeEach ->
        @hoodie.request.andReturn then: (success, error) =>
          # avoid recursion
          @hoodie.request.andReturn then: ->
          error status: 404, 'error object'
        
      it "should try again in 3 seconds (it migh be due to a sign up, the userDB might be created yet)", ->
        @remote.pull()
        expect(window.setTimeout).wasCalledWith @remote.pull, 3000

    _when "request errors with 500 oooops", ->
      beforeEach ->
        @hoodie.request.andReturn then: (success, error) =>
          # avoid recursion
          @hoodie.request.andReturn then: ->
          error status: 500, 'error object'
      
      it "should try again in 3 seconds (and hope it was only a hiccup ...)", ->
        @remote.pull()
        expect(window.setTimeout).wasCalledWith @remote.pull, 3000
        
      it "should trigger a server error event", ->
        @remote.pull()
        expect(@hoodie.trigger).wasCalledWith 'remote:error:server', 'error object'
        
    _when "request was aborted manually", ->
      beforeEach ->
        @hoodie.request.andReturn then: (success, error) =>
          # avoid recursion
          @hoodie.request.andReturn then: ->
          error statusText: 'abort', 'error object'
      
      it "should try again when remote is active", ->
        spyOn(@remote, "pull").andCallThrough()
        
        @remote.active = true
        @remote.pull()
        expect(@remote.pull.callCount).toBe 2
        
        @remote.pull.reset()
        @remote.active = false
        @remote.pull()
        expect(@remote.pull.callCount).toBe 1

    _when "there is a different error", ->
      beforeEach ->
        @hoodie.request.andReturn then: (success, error) =>
          # avoid recursion
          @hoodie.request.andReturn then: ->
          error {}, 'error object'
          
      it "should try again in 3 seconds if remote is active", ->
        @remote.active = true
        @remote.pull()
        expect(window.setTimeout).wasCalledWith @remote.pull, 3000
        
        window.setTimeout.reset()
        @remote.active = false
        @remote.pull()
        expect(window.setTimeout).wasNotCalledWith @remote.pull, 3000
  # /.pull()
  
  

  describe ".push(docs)", -> 
    beforeEach ->
      spyOn(Date, "now").andReturn 10
      @remote._timezoneOffset = 1
      @defer = @hoodie.defer()
      
    _when "no docs passed", ->        
      _and "there are no changed docs", ->
        beforeEach ->
          spyOn(@hoodie.my.localStore, "changedDocs").andReturn []
          @remote.push()
      
        it "shouldn't do anything", ->
          expect(@hoodie.request).wasNotCalled()
      
      _and "there is one deleted and one new doc", ->
        beforeEach ->
          spyOn(@hoodie.my.localStore, "changedDocs").andReturn Mocks.changedDocs()
          spyOn(@hoodie.my.account, "db").andReturn 'joe$examleCom'
          @remote.push()
          expect(@hoodie.request).wasCalled()
          [@method, @path, @options] = @hoodie.request.mostRecentCall.args
    
        it "should post the changes to the user's db _bulkDocs API", ->
          expect(@method).toBe 'POST'
          expect(@path).toBe '/joe%24examleCom/_bulkDocs'
      
        it "should set dataType to json", ->
          expect(@options.dataType).toBe 'json'
      
        it "should set processData to false", ->
          expect(@options.processData).toBe false
    
        it "should set contentType to 'application/json'", ->
          expect(@options.contentType).toBe 'application/json'
      
        it "should send the docs in appropriate format", ->
          {docs} = JSON.parse @options.data
          doc = docs[0]
          expect(doc.id).toBeUndefined()
          expect(doc._id).toBe 'todo/abc3'
          expect(doc._localInfo).toBeUndefined()

        it "should set data.newEdits to false", ->
          {newEdits} = JSON.parse @options.data
          expect(newEdits).toBe false

        it "should set new _revision ids", ->
          {docs} = JSON.parse @options.data
          [deletedDoc, newDoc] = docs
          expect(deletedDoc._rev).toBe '3-mock567#11'
          expect(newDoc._rev).toMatch '1-mock567#11'

          expect(deletedDoc._revisions.start).toBe 3
          expect(deletedDoc._revisions.ids[0]).toBe 'mock567#11'
          expect(deletedDoc._revisions.ids[1]).toBe '123'

          expect(newDoc._revisions.start).toBe 1
          expect(newDoc._revisions.ids[0]).toBe 'mock567#11'
      
      _when "Array of docs passed", ->
        beforeEach ->
          @todoObjects = [
            {type: 'todo', id: '1'}
            {type: 'todo', id: '2'}
            {type: 'todo', id: '3'}
          ]
          @remote.push @todoObjects
        
        it "should POST the passed objects", ->
          expect(@hoodie.request).wasCalled()
          data = JSON.parse @hoodie.request.mostRecentCall.args[2].data
          expect(data.docs.length).toBe 3
  # /.push(docs)
  
  describe ".sync(docs)", ->
    beforeEach ->
      spyOn(@remote, "push").andCallFake (docs) -> pipe: (cb) -> cb(docs)
      spyOn(@remote, "pull")
    
    it "should push changes and pass arguments", ->
      @remote.sync [1,2,3]
      expect(@remote.push).wasCalledWith [1,2,3]

    it "should pull changes and pass arguments", ->
      @remote.sync [1,2,3]
      expect(@remote.pull).wasCalledWith [1,2,3]
      
    _when "remote is active", ->
      beforeEach ->
        @remote.active = true
        
      it "should bind to store:dirty:idle event", ->
        @remote.sync()
        expect(@hoodie.on).wasCalledWith 'store:dirty:idle', @remote.push
        
      it "should unbind from store:dirty:idle event before it binds to it", ->
        order = []
        @hoodie.unbind.andCallFake (event) -> order.push "unbind #{event}"
        @hoodie.on.andCallFake (event) -> order.push "bind #{event}"
        @remote.sync()
        expect(order[0]).toBe 'unbind store:dirty:idle'
        expect(order[1]).toBe 'bind store:dirty:idle'
  # /.sync(docs)
  
  describe ".on(event, callback)", ->  
    it "should namespace events with `remote`", ->
      cb = jasmine.createSpy 'test'
      @remote.on 'funky', cb
      expect(@hoodie.on).wasCalledWith 'remote:funky', cb
  # /.on(event, callback)
# /Hoodie.RemoteStore