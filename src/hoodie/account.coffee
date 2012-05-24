#
# window.localStrage wrapper and more
#

define 'hoodie/account', ->
  
  # 'use strict'
  
  class Account
    
    # ## Properties
    email      : undefined
    
    # ## Constructor
    #
    constructor : (@hoodie) ->
      
      # handle evtl session
      @email = @hoodie.config.get '_account.email'
      @authenticate()
      
      @on 'signed_in',  @_handle_sign_in
      @on 'signed_out', @_handle_sign_out
    
    # ## Authenticate
    # 
    # Use this method to assure that the user is authenticated:
    # `hoodie.account.authenticate().done( do_something ).fail( handle_error )`
    authenticate : ->
      defer = @hoodie.defer()
      
      unless @email
        return defer.reject().promise()
        
      if @_authenticated is true
        return defer.resolve(@email).promise()
        
      if @_authenticated is false
        return defer.reject().promise()
      
      # @_authenticated is undefined
      @hoodie.request 'GET', "/_session"
      
        success     : (response) =>
          if response.userCtx.name
            @_authenticated = true
            @email = response.userCtx.name
            defer.resolve @email
          else
            @_authenticated = false
            @hoodie.trigger 'account:error:unauthenticated'
            defer.reject()
            
        error       : (xhr) ->
          try
            error = JSON.parse(xhr.responseText)
          catch e
            error = error: xhr.responseText or "unknown"
            
          defer.reject(error)
          
      return defer.promise()
      
      
        
    # ## sign up with email & password
    #
    # uses standard couchDB API to create a new document in _users db.
    # The backend will automatically create a userDB based on the email
    # address.
    #
    sign_up : (email, password, user_data = {}) ->
      defer = @hoodie.defer()
      
      key     = "#{@_prefix}:#{email}"

      data = 
        _id        : key
        name       : email
        type       : 'user'
        roles      : []
        user_data  : user_data
        password   : password

      @hoodie.request 'PUT', "/_users/#{encodeURIComponent key}",
        data        : JSON.stringify data
        contentType : 'application/json'
        
        success     : (response) =>
          @hoodie.trigger 'account:signed_up', email
          @hoodie.trigger 'account:signed_in', email;
          @fetch()
          defer.resolve email
          
        error       : (xhr) ->
          try
            error = JSON.parse(xhr.responseText)
          catch e
            error = error: xhr.responseText or "unknown"
            
          defer.reject(error)
        
      return defer.promise()


    # ## sign in with email & password
    #
    # uses standard couchDB API to create a new user session (POST /_session)
    #
    sign_in : (email, password) ->
      defer = @hoodie.defer()

      @hoodie.request 'POST', '/_session', 
        data: 
          name      : email
          password  : password
          
        success     : => 
          @hoodie.trigger 'account:signed_in', email
          @fetch()
          defer.resolve email
        
        error       : (xhr) ->
          try
            error = JSON.parse(xhr.responseText)
          catch e
            error = error: xhr.responseText or "unknown"
            
          defer.reject(error)
      
      return defer.promise()

    # alias
    login: @::sign_in


    # ## change password
    #
    # NOTE: simple implementation, current_password is ignored.
    #
    change_password : (current_password, new_password) ->
      defer = @hoodie.defer()
      unless @email
        defer.reject error: "unauthenticated", reason: "not logged in"
        return defer.promise()
      
      key = "#{@_prefix}:#{@email}"
      
      data = $.extend {}, @_doc
      delete data.salt
      delete data.password_sha
      data.password = new_password
      
      @hoodie.request 'PUT',  "/_users/#{encodeURIComponent key}",
        data        : JSON.stringify data
        contentType : "application/json"
        success     : (response) =>
          @fetch()
          defer.resolve()
          
        error       : (xhr) ->
          try
            error = JSON.parse(xhr.responseText)
          catch e
            error = error: xhr.responseText or "unknown"
            
          defer.reject(error)


    # ## sign out 
    #
    # uses standard couchDB API to destroy a user session (DELETE /_session)
    #
    # TODO: handle errors
    sign_out: ->
      @hoodie.request 'DELETE', '/_session', 
        success : => @hoodie.trigger 'account:signed_out'

    # alias
    logout: @::sign_out
    
    # ## On
    #
    # alias for `hoodie.on`
    on : (event, cb) -> @hoodie.on "account:#{event}", cb
    
    # ## db
    #
    # escape user email (or what ever he uses to sign up)
    # to make it a valid couchDB database name
    # 
    #     Converts an email address user name to a valid database name
    #     The character replacement rules are:
    #       [A-Z] -> [a-z]
    #       @ -> $
    #       . -> _
    #     Notes:
    #      can't reverse because _ are valid before the @.
    #
    #
    db : -> 
      @email?.toLowerCase().replace(/@/, "$").replace(/\./g, "_");
      
    # ## fetch
    #
    # fetches _users doc from CouchDB and caches it in _doc
    fetch : ->
      defer = @hoodie.defer()
      unless @email
        defer.reject error: "unauthenticated", reason: "not logged in"
        return defer.promise()
      
      key = "#{@_prefix}:#{@email}"
      @hoodie.request 'GET', "/_users/#{encodeURIComponent key}",
      
        success     : (response) => 
          @_doc = response
          defer.resolve response
        
        error       : (xhr) ->
          try
            error = JSON.parse(xhr.responseText)
          catch e
            error = error: xhr.responseText or "unknown"
            
          defer.reject(error) 
          
      return defer.promise()
      
    user_data : ->
      @_doc?.user_data

    # ## PRIVATE
    #
    _prefix : 'org.couchdb.user'
    
    # couchDB _users doc
    _doc : {}
    
    #
    _handle_sign_in: (@email) =>
      @hoodie.config.set '_account.email', @email
      @_authenticated = true
    
    #
    _handle_sign_out: =>
      delete @email
      @hoodie.config.remove '_account.email'
      @_authenticated = false