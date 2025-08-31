ENV['KEY_EXPIRY_SECONDS'] = '3'
ENV['KEY_BLOCK_SECONDS']  = '1'
ENV['KEY_POLL_INTERVAL']  = '0.05'

require_relative '../server'
require_relative 'spec_helper'
require 'json'

RSpec.describe 'API Key Server (app)' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  it 'creates a key' do
    post '/keys'
    expect(last_response.status).to eq(201)
    body = JSON.parse(last_response.body)
    expect(body['key']).to be_a(String)
    expect(body['expiry_at']).to be_a(String)
  end

  it 'gets an available key then 404 when none available' do
    post '/keys'
    key = JSON.parse(last_response.body)['key']

    get '/keys/available'
    expect(last_response.status).to eq(200)
    served = JSON.parse(last_response.body)['key']
    expect(served).to eq(key)

    # Since only one key and it's blocked, next call should 404
    get '/keys/available'
    expect(last_response.status).to eq(404)
  end

  it 'can unblock and then serve again' do
    post '/keys'
    key = JSON.parse(last_response.body)['key']

    get '/keys/available'
    expect(last_response.status).to eq(200)

    post "/keys/#{key}/unblock"
    expect(last_response.status).to eq(200)

    get '/keys/available'
    expect(last_response.status).to eq(200)
  end

  it 'delete key' do
    post '/keys'
    key = JSON.parse(last_response.body)['key']

    delete "/keys/#{key}"
    expect(last_response.status).to eq(200)

    get "/keys/#{key}"
    expect(last_response.status).to eq(404)
  end

  it 'keep alive works' do
    post '/keys'
    key = JSON.parse(last_response.body)['key']

    post "/keys/#{key}/keep_alive"
    expect(last_response.status).to eq(200)
  end
end
