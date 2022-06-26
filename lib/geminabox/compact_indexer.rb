require 'fileutils'

module Geminabox
  module CompactIndexer
    class << self

      def clear_index
        FileUtils.rm_rf(compact_index_path)
        FileUtils.mkdir_p(info_path)
      end

      def reindex_versions(data)
        File.binwrite(versions_path, data)
      end

      def reindex_info(name, data)
        File.binwrite(info_name_path(name), data)
      end

      def fetch_versions
        path = versions_path
        File.binread(path) if File.exist?(path)
      end

      def fetch_info(name)
        path = info_name_path(name)
        File.binread(path) if File.exist?(path)
      end

      def compact_index_path
        File.expand_path(File.join(Geminabox.data, 'compact_index'))
      end

      def versions_path
        File.join(compact_index_path, 'versions')
      end

      def info_path
        File.join(compact_index_path, 'info')
      end

      def info_name_path(name)
        File.join(info_path, name)
      end

      def log_time(text)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
      ensure
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        printf("%s: %.2f seconds\n", text, end_time - start_time)
      end

      def incremental_reindex_compact_cache(gem_specs)
        version_info = VersionInfo.new
        version_info.load_versions

        gem_specs.group_by(&:name).each do |name, specs|
          info = DependencyInfo.new(name)
          data = CompactIndexer.fetch_info(name)
          info.content = data if data
          specs.each do |spec|
            gem_version = GemVersion.new(name, spec.version, spec.platform)
            checksum = Specs.checksum_for_version(gem_version)
            info.add_gem_spec_and_gem_checksum(spec, checksum)
          end
          CompactIndexer.reindex_info(name, info.content)
          version_info.update_gem_versions(info)
        end

        version_info.write
      end

      def all_specs
        Geminabox::GemVersionCollection.new(Specs.all_gems)
      end

      def full_reindex_compact_cache
        CompactIndexer.clear_index
        version_info = VersionInfo.new

        all_specs.by_name.to_h.each do |name, versions|
          info = dependency_info(versions)
          CompactIndexer.reindex_info(name, info.content)
          version_info.update_gem_versions(info)
        end

        version_info.write
      end

      def reindex_compact_cache(specs = nil)
        return unless Geminabox.index_format

        if specs && File.exist?(CompactIndexer.versions_path)
          log_time("compact index incremental reindex") do
            incremental_reindex_compact_cache(specs)
          end
          return
        end

        log_time("compact index full rebuild") do
          full_reindex_compact_cache
        end
      rescue SystemCallError => e
        CompactIndexer.clear_index
        puts "Compact index error #{e.message}\n"
      end

      def dependency_info(gem)
        DependencyInfo.new(gem.first.name) do |info|
          gem.by_name do |_name, versions|
            versions.each do |version|
              spec = Specs.spec_for_version(version)
              next unless spec

              checksum = Specs.checksum_for_version(version)
              next unless checksum

              info.add_gem_spec_and_gem_checksum(spec, checksum)
            end
          end
        end
      end
    end
  end
end
