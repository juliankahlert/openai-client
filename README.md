# OpenAI Client Library
This repository contains a simple OpenAI client library written in Ruby, along with some example programs demonstrating its usage. The examples include an interactive chat CLI application that allows users to chat with an OpenAI assistant.
I created this for personal use, but others might find it useful as well.

## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
  - [OpenAI Client Library](#openai-client-library)
  - [Interactive Chat CLI](#interactive-chat-cli)
- [Configuration](#configuration)
- [License](#license)

## Installation

1. Clone the repository:
   ```sh
   https://github.com/juliankahlert/openai-client.git
   cd openai-client
   ```

2. Install required gems:
   ```sh
   gem install net-http json yaml base64
   ```

## Usage

### OpenAI Client Library

The `OpenAI` class provides a simple interface for interacting with the OpenAI API. Below is a basic example of how to use it in your Ruby programs.

```ruby
require_relative 'lib/openai'

config = {
  config_file: '.openai.yaml',
  token: ENV['OPENAI_API_KEY'],
  model_string: 'gpt-4o-2024-05-13'
}

openai = OpenAI.new(config)
session = openai.new_session()

session.append do |sess|
  sess.new_message()
      .role('system')
      .text('You are a helpful assistant.')
end

session.append do |sess|
  sess.new_message()
      .role('user')
      .text('Hi!')
end

response = openai.new_request do |req|
  req.attach_session(session)
end

if response.success?
  puts response.completion
else
  puts "Error: #{response.error}"
end```

### Interactive Chat CLI

The repository includes some example programs including an interactive chat CLI that communicates with an OpenAI assistant.

Run the ai-chat script:
   ```sh
   ai-chat --token OPENAI_TOKEN --history-file chat.history
   ```

   This will start an interactive chat session where you can type messages and receive responses from the assistant.

## Configuration

The OpenAI client library expects a configuration file named `.openai.yaml` in the working directory. This file should contain the necessary settings for the OpenAI API. Here is an example configuration:

```yaml
---
openai:
  model: "gpt-4o-2024-05-13"
  params:
    max-tokens: 150
    temperature: 0.7
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for more details.

---

Feel free to contribute to this repository by submitting issues or pull requests. We welcome any improvements or additional examples that can help demonstrate the capabilities of the OpenAI client library.
