require 'rack/test'
require 'rspec'

ENV['RACK_ENV'] = 'test'

# set test timeouts BEFORE loading server if you rely on ENV in server.rb
ENV['KEY_EXPIRY_SECONDS'] = ENV['KEY_EXPIRY_SECONDS'] || '3'
ENV['KEY_BLOCK_SECONDS']  = ENV['KEY_BLOCK_SECONDS']  || '1'
ENV['KEY_POLL_INTERVAL']  = ENV['KEY_POLL_INTERVAL']  || '0.05'

require_relative '../server'

# Reset the KEY_STORE's internal state before each example so tests are isolated.
RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.before(:each) do
    if defined?(KEY_STORE)
      # Synchronize using the store's mutex if present
      mutex = KEY_STORE.instance_variable_get(:@mutex)
      if mutex
        mutex.synchronize do
          KEY_STORE.instance_variable_set(:@keys, {})
          KEY_STORE.instance_variable_set(:@available_keys, [])
          KEY_STORE.instance_variable_set(:@available_index, {})
          # Reset heaps to fresh instances (MinHeap defined in key_store)
          KEY_STORE.instance_variable_set(:@expiry_heap, MinHeap.new)
          KEY_STORE.instance_variable_set(:@block_heap, MinHeap.new)
        end
      else
        # Fallback if no mutex
        KEY_STORE.instance_variable_set(:@keys, {})
        KEY_STORE.instance_variable_set(:@available_keys, [])
        KEY_STORE.instance_variable_set(:@available_index, {})
        KEY_STORE.instance_variable_set(:@expiry_heap, MinHeap.new)
        KEY_STORE.instance_variable_set(:@block_heap, MinHeap.new)
      end
    end
  end
end

def app
  Sinatra::Application
end
