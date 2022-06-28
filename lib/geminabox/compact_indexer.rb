require 'fileutils'

module Geminabox
  class CompactIndexer

    class << self

      def clear_index
        FileUtils.rm_rf(compact_index_path)
        FileUtils.mkdir_p(info_path)
      end

      def fetch_versions
        path = versions_path
        File.binread(path) if File.exist?(path)
      end

      def fetch_info(name)
        path = info_name_path(name)
        File.binread(path) if File.exist?(path)
      end

      def compact_index_path(base_path = Geminabox.data)
        File.expand_path(File.join(base_path, 'compact_index'))
      end

      def versions_path(base_path = compact_index_path)
        File.join(base_path, 'versions')
      end

      def info_path(base_path = compact_index_path)
        File.join(base_path, 'info')
      end

      def info_name_path(name, base_path = info_path)
        File.join(base_path, name)
      end
    end

    def reindex(specs = nil)
      return unless Geminabox.compact_index

      if specs && File.exist?(CompactIndexer.versions_path)
        log_time("compact index incremental reindex") do
          incremental_reindex(specs)
        end
        return
      end

      log_time("compact index full rebuild") do
        full_reindex
      end
    end

    private

    def log_time(text)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      printf("%s: %.2f seconds\n", text, end_time - start_time)
    end

    def incremental_reindex(gem_specs)
      directory = Dir.mktmpdir("geminabox-compact-index")
      compact_index_path = CompactIndexer.compact_index_path(directory)
      info_path = CompactIndexer.info_path(compact_index_path)
      FileUtils.mkdir_p(info_path)

      version_info = VersionInfo.new
      version_info.load_versions

      updated_files = update_info_files(gem_specs, info_path, version_info)

      file_path = CompactIndexer.versions_path(compact_index_path)
      updated_files << [file_path, CompactIndexer.versions_path]
      version_info.write(file_path)

      updated_files.each do |src, dest|
        FileUtils.mv(src, dest)
      end
    ensure
      FileUtils.rm_rf(directory)
    end

    def update_info_files(gem_specs, info_path, version_info)
      updated_files = []
      gem_specs.group_by(&:name).each do |name, specs|
        info = DependencyInfo.new(name)
        data = CompactIndexer.fetch_info(name)
        info.content = data if data
        specs.each do |spec|
          gem_version = GemVersion.new(name, spec.version, spec.platform)
          checksum = Specs.checksum_for_version(gem_version)
          info.add_gem_spec_and_gem_checksum(spec, checksum)
        end
        file_path = CompactIndexer.info_name_path(name, info_path)
        updated_files << [file_path, CompactIndexer.info_name_path(name)]
        File.binwrite(file_path, info.content)
        version_info.update_gem_versions(info)
      end
      updated_files
    end

    def all_specs
      Geminabox::GemVersionCollection.new(Specs.all_gems)
    end

    def full_reindex
      CompactIndexer.clear_index
      version_info = VersionInfo.new

      all_specs.by_name.to_h.each do |name, versions|
        info = dependency_info(versions)
        file = CompactIndexer.info_name_path(name)
        File.binwrite(file, info.content)
        version_info.update_gem_versions(info)
      end

      version_info.write
    end

    def dependency_info(gem)
      name, versions = gem.by_name.first
      info = DependencyInfo.new(name)
      versions.each do |version|
        spec = Specs.spec_for_version(version)
        checksum = Specs.checksum_for_version(version) if spec
        info.add_gem_spec_and_gem_checksum(spec, checksum) if checksum
      end
      info
    end

  end
end
