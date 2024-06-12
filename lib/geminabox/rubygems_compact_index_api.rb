require 'uri'
require 'open-uri'

module Geminabox
  class RubygemsCompactIndexApi
    include CompactIndexer::PathMethods

    def fetch_info(gem_name, etag = nil)
      fetch("/info/#{gem_name}", etag)
    end

    def fetch_versions(etag = nil)
      fetch('/versions', etag)
    end

    def download_versions(etag, cache)
      download('/versions', etag, cache)
    end

    def fetch_names(etag = nil)
      fetch('/names', etag)
    end

    private

    def fetch(path, etag)
      headers = { 'If-None-Match' => %("#{etag}") } if etag
      response = Geminabox.http_adapter.get(rubygems_uri(path), nil, headers)
      [response.code, response.body]
    rescue StandardError
      return [0, nil] if Geminabox.allow_remote_failure

      raise
    end

    def download(path, etag, cache)
      headers = {}
      headers['If-None-Match'] = %("#{etag}") if etag
      proxy_versions_path = "#{cache.cache_path}#{path}"
      case io = OpenURI::open_uri(rubygems_uri(path), **(headers))
      when StringIO then File.open(proxy_versions_path, 'w') { |f| f.write(io.read) }
      when Tempfile then io.close; FileUtils.cp(io.path, proxy_versions_path)
      end
      [200, "#{cache.cache_path}#{path} updated."]
    rescue OpenURI::HTTPError => e
      return [304, nil] if e.message.include?('304')
      raise
    rescue StandardError
      return [0, nil] if Geminabox.allow_remote_failure
      raise
    end

    def rubygems_uri(path)
      URI.join(Geminabox.bundler_ruby_gems_url, path)
    end

  end
end
