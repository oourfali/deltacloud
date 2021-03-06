require 'rubygems'
require 'require_relative' if RUBY_VERSION < '1.9'

require_relative 'common.rb'

describe Deltacloud do

  before do
    Deltacloud::configure :cimi do |server|
      server.root_url '/cimi'
      server.version Deltacloud::API_VERSION
      server.klass 'CIMI'
      server.logger Logger
    end
  end

  it 'should return the servers configuration' do
    Deltacloud.config.must_be_kind_of Hash
    Deltacloud.config.keys.must_include :deltacloud
    Deltacloud.config.keys.must_include :cimi
    Deltacloud.config[:deltacloud].must_be_kind_of Deltacloud::Server
  end

  it 'should be able to require the correct frontned' do
    Deltacloud[:deltacloud].klass.must_equal Deltacloud::API
  end

  it 'should not require already required frontend' do
    Deltacloud.require_frontend!.must_equal false
  end

  describe Deltacloud::Server do

    it 'should provide the correct root_url' do
      Deltacloud.config[:deltacloud].root_url.must_equal '/api'
      Deltacloud.config[:cimi].root_url.must_equal '/cimi'
    end

    it 'should provide the correct version' do
      Deltacloud.config[:deltacloud].version.must_equal Deltacloud::API_VERSION
      Deltacloud.config[:cimi].version.must_equal Deltacloud::API_VERSION
    end

    it 'should provide the logger facility' do
      Deltacloud.config[:deltacloud].logger.must_equal Rack::DeltacloudLogger
      Deltacloud.config[:cimi].logger.must_equal Logger
    end

  end

end
