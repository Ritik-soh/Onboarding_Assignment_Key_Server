require_relative '../lib/key_store'
require 'time'
require_relative 'spec_helper'

RSpec.describe KeyStore do
  let(:expiry_seconds) { 2 }   
  let(:block_seconds)  { 1 }   
  let(:poll_interval)  { 0.05 } 

  it 'generates a key and returns info' do
    ks = KeyStore.new(expiry_seconds: expiry_seconds, block_seconds: block_seconds, poll_interval: poll_interval)
    k = ks.generate_key
    expect(k).to be_a(String)
    info = ks.info(k)
    expect(info).not_to be_nil
    expect(info[:blocked]).to be false
  end

  it 'serves an available key and blocks it' do
    ks = KeyStore.new(expiry_seconds: expiry_seconds, block_seconds: block_seconds, poll_interval: poll_interval)
    k = ks.generate_key
    served = ks.get_available_key
    expect(served).to eq(k)
    info = ks.info(k)
    expect(info[:blocked]).to be true
  end

  it 'auto-releases blocked key after block_seconds' do
    ks = KeyStore.new(expiry_seconds: expiry_seconds, block_seconds: block_seconds, poll_interval: poll_interval)
    k = ks.generate_key
    ks.get_available_key
    sleep(block_seconds + poll_interval + 0.05)
    info = ks.info(k)
    expect(info).not_to be_nil
    expect(info[:blocked]).to be false
  end

  it 'expires key if no keep_alive' do
    ks = KeyStore.new(expiry_seconds: 1, block_seconds: block_seconds, poll_interval: poll_interval)
    k = ks.generate_key
    sleep 1 + poll_interval + 0.05
    expect(ks.info(k)).to be_nil
  end

  it 'unblock_key resets expiry and makes available' do
    ks = KeyStore.new(expiry_seconds: expiry_seconds, block_seconds: block_seconds, poll_interval: poll_interval)
    k = ks.generate_key
    ks.get_available_key
    ok = ks.unblock_key(k)
    expect(ok).to be true
    info = ks.info(k)
    expect(info[:blocked]).to be false
  end

  it 'keep_alive extends expiry' do
    ks = KeyStore.new(expiry_seconds: 2, block_seconds: block_seconds, poll_interval: poll_interval)
    k = ks.generate_key
    expect(ks.keep_alive(k)).to be true
    info1 = ks.info(k)
    expect(info1[:expiry]).to be > Time.now.to_f
  end
end
