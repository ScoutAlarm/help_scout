require "help_scout/version"
require "oauth2"
require "httparty"

class HelpScout
  class ValidationError < StandardError; end
  class NotImplementedError < StandardError; end
  class NotFoundError < StandardError; end
  class TooManyRequestsError < StandardError; end
  class InternalServerError < StandardError; end
  class ForbiddenError < StandardError; end
  class ServiceUnavailable < StandardError; end
  class UnauthorizedError < StandardError; end

  # Status codes used by Help Scout, not all are implemented in this gem yet.
  # http://developer.helpscout.net/help-desk-api/status-codes/
  HTTP_OK = 200
  HTTP_CREATED = 201
  HTTP_NO_CONTENT = 204
  HTTP_BAD_REQUEST = 400
  HTTP_UNAUTHORIZED = 401
  HTTP_FORBIDDEN = 403
  HTTP_NOT_FOUND = 404
  HTTP_TOO_MANY_REQUESTS = 429
  HTTP_INTERNAL_SERVER_ERROR = 500
  HTTP_SERVICE_UNAVAILABLE = 503

  attr_accessor :last_response

  def initialize(options = {})
    @client_id = options[:client_id]
    @client_secret = options[:client_secret]
    get_token()
    self
  end

  def get_token
    client = OAuth2::Client.new(@client_id, @client_secret, :site => 'https://api.helpscout.net', token_url: '/v2/oauth2/token')
    response = client.client_credentials.get_token
    unless response.token.present?
      raise UnauthorizedError
    end
    @token = response.token
  end

  # Public: Create conversation
  #
  # data - hash with data
  #
  # More info: https://developer.helpscout.com/mailbox-api/endpoints/conversations/create/
  #
  # Returns conversation ID
  def create_conversation(data)
    post("conversations", { body: data })

    # Extract ID of created conversation from the Location header
    conversation_uri = last_response.headers["location"]
    conversation_uri.match(/(\d+)$/)[1]
  end

  # Public: Get conversation
  #
  # id - conversation ID
  #
  # More info: http://developer.helpscout.net/help-desk-api/objects/conversation/
  #
  # Returns hash from HS with conversation data
  def get_conversation(id)
    get("conversations/#{id}")
  end

  # Public: Get conversations
  #
  # mailbox_id - ID of mailbox (find these with get_mailboxes)
  # page - integer of page to fetch (default: 1)
  # modified_since - Only return conversations that have been modified since
  #                  this UTC datetime (default: nil)
  #
  # More info: http://developer.helpscout.net/help-desk-api/conversations/list/
  #
  # Returns hash from HS with conversation data
  def get_conversations(id, query = {})
    options = {
      query: query.merge(mailbox: id)
    }

    get("conversations", options)
  end

  # Public: Update conversation
  #
  # id - conversation id
  # data - hash with data
  #
  # More info: http://developer.helpscout.net/help-desk-api/conversations/update/
  def update_conversation(id, data)
    put("conversations/#{id}", { body: data })
  end

  # Public: Search for conversations
  #
  # query - term to search for
  #
  # More info: http://developer.helpscout.net/help-desk-api/search/conversations/
  def search_conversations(query)
    search("search/conversations", query)
  end

  # Public: Delete conversation
  #
  # id - conversation id
  #
  # More info: https://developer.helpscout.com/help-desk-api/conversations/delete/
  def delete_conversation(id)
    delete("conversations/#{id}")
  end

  # Public: Get customer
  #
  # id - customer id
  #
  # More info: http://developer.helpscout.net/help-desk-api/customers/get/
  def get_customer(id)
    get("customers/#{id}")
  end

  def get_mailboxes
    get("mailboxes")
  end

  # Public: Get ratings
  #
  # More info: http://developer.helpscout.net/help-desk-api/reports/user/ratings/
  # 'rating' parameter required: 0 (for all ratings), 1 (Great), 2 (Okay), 3 (Not Good)
  def reports_user_ratings(user_id, rating, start_date, end_date, options)
    options = {
      user: user_id,
      rating: rating,
      start: start_date,
      end: end_date,
    }

    get("reports/user/ratings", options)
  end

  # Public: Creates conversation thread
  #
  # conversion_id - conversation id
  # body - thread content to be created
  #
  # More info: https://developer.helpscout.com/mailbox-api/endpoints/conversations/threads/chat/
  #
  # Returns true if created, false otherwise.
  def create_chat_thread(conversation_id, body)
    post("conversations/#{conversation_id}/chats", body: body)
    last_response.code == HTTP_CREATED
  end

  def create_reply_thread(conversation_id, body)
    post("conversations/#{conversation_id}/reply", body: body)
    last_response.code == HTTP_CREATED
  end

  def create_notes_thread(conversation_id, body)
    post("conversations/#{conversation_id}/notes", body: body)
    last_response.code == HTTP_CREATED
  end

  # Public: Updates conversation thread
  #
  # conversion_id - conversation id
  # thread - thread content to be updated (only the body can be updated)
  # reload - Set to true to get the entire conversation in the result
  #
  # More info: http://developer.helpscout.net/help-desk-api/conversations/update-thread/
  #
  # Returns true if updated, false otherwise. When used with reload: true it
  # will return the entire conversation
  def update_thread(conversation_id:, thread_id:, op:, path:, value:)
    body = {}
    body[:op] = op
    body[:path] = path
    body[:value] = value

    patch("conversations/#{conversation_id}/threads/#{thread_id}", body: body.to_json)

    last_response.code == HTTP_NO_CONTENT
  end


  def get_threads(conversion_id:)
    get("conversations/#{conversion_id}/threads")
  end

  def search_threads(conversion_id:)
    search("conversations/#{conversion_id}/threads")
  end

  # Public: Update Customer
  #
  # id - customer id
  # data - hash with data
  #
  # More info: http://developer.helpscout.net/help-desk-api/customers/update/
  def update_customer(id, data)
    put("customers/#{id}", { body: data })
  end

  def post(path, options = {})
    options[:body] = options[:body].to_json if options[:body]

    request(:post, path, options)
  end

  def put(path, options = {})
    options[:body] = options[:body].to_json if options[:body]

    request(:put, path, options)
  end

  def get(path, options = {})
    request(:get, path, options)
  end

  def delete(path, options = {})
    request(:delete, path, options)
  end

  def patch(path, options = {})
    request(:patch, path, options)
  end

  def search(path, query = {}, page_id = 1, items = [])
    options = { query: query.merge(page: page_id) }

    result = get(path, options)
    if !result.empty?
      next_page_id = page_id + 1
      _items = result["_embedded"].first.second
      _items += items
      if next_page_id > result["page"]["totalPages"]
        return _items
      else
        search(path, query, next_page_id, _items)
      end
    end
  end

  protected

  def request(method, path, options)
    uri = URI("https://api.helpscout.net/v2/#{path}")

    options = {
      headers: {
        "Authorization" => "Bearer #{@token}"
      }
    }.merge(options)

    if options.key?(:body)
      options[:headers]['Content-Type'] ||= 'application/json; charset=UTF-8'
    end
    @last_response = HTTParty.send(method, uri, options)
    case last_response.code
    when HTTP_UNAUTHORIZED
      error_message = JSON.parse(last_response.body)
      raise UnauthorizedError, error_message
    when HTTP_OK, HTTP_CREATED, HTTP_NO_CONTENT
      last_response.parsed_response
    when HTTP_BAD_REQUEST
      raise ValidationError, last_response.parsed_response["validationErrors"]
    when HTTP_FORBIDDEN
      raise ForbiddenError
    when HTTP_NOT_FOUND
      raise NotFoundError
    when HTTP_INTERNAL_SERVER_ERROR
      error_message = JSON.parse(last_response.body)["error"]
      raise InternalServerError, error_message
    when HTTP_SERVICE_UNAVAILABLE
      raise ServiceUnavailable
    when HTTP_TOO_MANY_REQUESTS
      retry_after = last_response.headers["Retry-After"]
      message = "Rate limit of 400 RPM or 12 POST/PUT/DELETE  will count as 2 requests." +
        "Next request possible in #{retry_after} seconds."
      raise TooManyRequestsError, message
    else
      raise NotImplementedError, "Help Scout returned something that is not implemented by the help_scout gem yet: #{last_response.code}: #{last_response.parsed_response["message"] if last_response.parsed_response}"
    end
  end
end
