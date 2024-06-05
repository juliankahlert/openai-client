#!/bin/env ruby
#
# MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require "net/http"
require "base64"
require "json"
require "yaml"

# Example usage of OpenAI class
#
# openai = OpenAI.new(options)
# session = openai.new_session()
#
# session.enable_auto_sync('chat.history') do
#   session.append do |sess|
#     sess.new_message("system")
#         .text("You are a helpfull assistent.")
#   end
# end
#
# session.append do |sess|
#   sess.new_message()
#       .role('user')
#       .text(THE_PROMPT)
# end
#
# response = openai.new_request do |req|
#   req.attach_session(session)
# end
#
# if response.success?
#  if response.completion
#    puts response.completion
#    session.append do |sess|
#      sess.new_message()
#          .role('assistant')
#          .text(response.completion)
#    end
#   end
# end
class OpenAI
  class Message
    def initialize(openai, role = "user")
      @role = role
      @openai = openai
    end

    def dup
      clone = Message.new(@openai, @role.dup)
      clone.text(@text.dup)
      clone.image_data(@image.dup)
      clone
    end

    def text(data)
      @text = data
      self
    end

    def role(data)
      @role = data
      self
    end

    def image(path)
      return self unless path

      data = @openai.encode_file_as_base64(path)
      @image = "data:image/png;base64,#{data}"
      self
    end

    def image_data(data)
      @image = data
      self
    end

    def to_h
      message = { "role" => @role }

      if @image
        message["content"] = []
        message["content"] << {
          "type" => "image_url",
          "image_url" => {
            "url" => @image,
          },
        }

        if @text
          message["content"] << {
            "type" => "text",
            "text" => @text,
          }
        end
      elsif @text
        message["content"] = @text
      end

      message
    end
  end

  class Session
    def initialize(openai, history = [])
      @history = history
      @openai = openai
      @auto_sync_file = nil
    end

    def dup
      OpenAI::Session.new(@openai, @history.dup)
    end

    def dump
      @history.dup
    end

    def new_message(role = "user", &block)
      m = OpenAI::Message.new(@openai, role)
      block.call(m) if block
      m
    end

    def enable_auto_sync(path, &block)
      @auto_sync_file = path
      if path && File.exist?(path)
        @history = []
        File.open(path, "r") do |file|
          file.each_line do |line|
            @history << JSON.parse(line)
          end
        end
      else
        block.call if block
      end
    end

    def auto_sync
      return unless @auto_sync_file

      new_msg = @history.last
      return unless new_msg

      File.write(@auto_sync_file, new_msg.to_h.to_json.to_s + "\n", mode: "a+")
    end

    def self.load(path)
      return self.new unless path

      history = []
      File.read(path).split("\n").map do |line|
        history << JSON.parse(line)
      end

      self.new(history)
    end

    def append(message = nil, &block)
      message ||= block.call(self)
      @history << message.to_h
      auto_sync
    end
  end

  class ResponseBuilder
    class Response
      attr_reader :request, :completion, :error, :function_call

      def initialize(request, success, error, completion, function_call)
        @request = request
        @success = success
        @error = error
        @completion = completion
        @function_call = function_call
      end

      def success?
        @success == true
      end
    end

    def initialize(request)
      @request = request
      @valid = true
    end

    def success(value = true)
      @success = value
      self
    end

    def error(value)
      @error = value
      self
    end

    def function_call(call)
      @function_call = call
      self
    end

    def completion(data)
      @completion = data
      self
    end

    def self.success(request)
      builder = ResponseBuilder.new(request)
      builder.success(true)
    end

    def self.fail(request, error)
      builder = ResponseBuilder.new(request)
      builder.success(false).error(error)
    end

    def seal
      return nil unless @valid

      r = Response.new(@request,
                       @success,
                       @error,
                       @completion,
                       @function_call)

      @valid = false
      r
    end
  end

  class Request
    def initialize(openai)
      @openai = openai
    end

    def attach_tools(tools)
      @tools = tools
      self
    end

    def attach_session(session = nil)
      session = OpenAI::Session.new unless session
      @session = session
      self
    end

    def session
      @session ||= attach_session
      @session
    end

    def fail(error)
      OpenAI::ResponseBuilder.fail(self, error)
    end

    def success
      OpenAI::ResponseBuilder.success(self)
    end

    def prepare
      request = Net::HTTP::Post.new(@openai.uri)
      request.content_type = "application/json"
      request["Authorization"] = "Bearer #{@openai.token}"

      body = {
        "model" => @openai.model,
        "max_tokens" => @openai.max_tokens,
        "n" => @openai.n,
        "top_p" => 0.1,
        "temperature" => 0.2,
        "messages" => @session.dump,
      }
      body["functions"] = @tools.array if @tools

      request.body = body.to_json
      @request = request
      self
    end

    def run
      return fail("ERROR: request not prepared").seal unless @request

      host = @openai.uri.hostname
      port = @openai.uri.port

      response = Net::HTTP.start(host, port, use_ssl: true) do |http|
        http.read_timeout = 600
        http.request(@request)
      end
      @request = nil

      if response.is_a?(Net::HTTPSuccess)
        parsed_response = JSON.parse(response.body)
        function_call = parsed_response["choices"][0]["message"]["function_call"]
        @tools.try_call(function_call) if @tools

        completion = parsed_response["choices"][0]["message"]["content"]
        if completion
          completion = completion.to_s + "\n"
          completion = completion.gsub(/^```.*\n/, "")
        end
      else
        return fail("Error: #{response.message}").seal
      end

      return success().function_call(function_call)
                      .completion(completion)
                      .seal
    rescue StandardError => e
      return fail(e.to_s).seal
    end
  end

  attr_reader :token, :uri

  def initialize(config)
    @cfg = config[:config_file]
    @cfg ||= find_cfg
    @token = config[:token]
    @model = config[:model_string]
    @model ||= model
    @uri = URI("https://api.openai.com/v1/chat/completions")

    sanity_check
  end

  def new_request(&block)
    r = Request.new(self)
    return block.call(r).prepare.run if block
    r
  end

  def new_session(&block)
    s = Session.new(self)
    block.call(s) if block
    s
  end

  def new_message(role = "user", &block)
    m = Message.new(self, role)
    block.call(m) if block
    m
  end

  def model
    return @model if @model

    return nil unless @cfg
    return nil unless @cfg["openai"]
    return nil unless @cfg["openai"]["model"]

    @model = @cfg["openai"]["model"]
    @model
  end

  def max_tokens
    return @max_tokens if @max_tokens

    default = 150
    return default unless @cfg
    return default unless @cfg["openai"]
    return default unless @cfg["openai"]["params"]
    return default unless @cfg["openai"]["params"]["max-tokens"]

    @max_tokens = @cfg["openai"]["params"]["max-tokens"]
    @max_tokens
  end

  def n
    return @n if @n

    default = 1
    return default unless @cfg
    return default unless @cfg["openai"]
    return default unless @cfg["openai"]["params"]
    return default unless @cfg["openai"]["params"]["n"]

    @n = @cfg["openai"]["params"]["n"]
    @n
  end

  def temperature
    return @temperature if @temperature

    default = 0.7
    return default unless @cfg
    return default unless @cfg["openai"]
    return default unless @cfg["openai"]["params"]
    return default unless @cfg["openai"]["params"]["temperature"]

    @temperature = @cfg["openai"]["params"]["temperature"]
    @temperature
  end

  def die(msg)
    STDERR.puts(msg.to_s)
    exit(1)
  end

  def sanity_check
    die("Error: .openai.yaml not found") unless @cfg
    die("Error: Token not found") unless @token
    die("Error: Model missing") unless @model
  end

  def find_cfg
    pwd = Dir.pwd
    dirs = pwd.split("/")
    cfg = nil
    (dirs.size + 1).times do |i|
      path = dirs[0, dirs.size - i].join("/") + "/.openai.yaml"
      if File.exist?(path)
        cfg = YAML.load_file(path)
        break
      end
    end
    cfg
  end

  def encode_file_as_base64(file_path)
    unless File.exist?(file_path.to_s)
      puts "File not found: <#{file_path}>"
      return nil
    end

    file_content = File.binread(file_path)
    encoded_content = Base64.strict_encode64(file_content)

    return encoded_content
  end
end
