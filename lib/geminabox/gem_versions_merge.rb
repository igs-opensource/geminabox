require 'time'

module Geminabox
  module GemVersionsMerge
    extend CompactIndexer::PathMethods

    def self.datadir
      Geminabox.data
    end

    def self.merge(local_gem_list)
      return local_gem_list unless File.exist?(proxy_versions_path)
      File.open(proxy_versions_path) do |remote_versions_file|
        StringIO.open(local_gem_list) do |local_io|
          remote_preamble = remote_versions_file.readline
          local_preamble = local_io.readline
          remote_time = Time.parse(remote_preamble.split[1])
          local_time = Time.parse(local_preamble.split[1])
          preamble = (local_time > remote_time ? local_preamble : remote_preamble)
          try_load_cached_file do |merged_versions_file|
            unless merged_versions_file.eof?
              merged_versions_preamble = merged_versions_file.readline
              merged_version_time = Time.parse(merged_versions_preamble.split[1])
              preamble_time = Time.parse(preamble.split[1])
              if merged_version_time >= preamble_time
                merged_versions_file.rewind
                merged_versions_file.read
              end
            end
          end

          write_version_entries(local_io, remote_versions_file)
          File.read(merged_versions_path)
        end
      end

    end

    def self.write_version_entries(local_gem_io, remote_version_io)
      try_load_cached_file('w') do |merged_versions_file|
        local_gem_list = local_gem_io.readlines[1..-1].map { |it| it.split[0] }
        local_gem_io.rewind
        local_gem_io.readline # advance past preamble since we're writing our own merged versions file
        preamble = "created_at: #{Time.now}"
        merged_versions_file.flock(File::LOCK_EX)
        merged_versions_file.write("#{preamble}\n")
        merged_versions_file.write(local_gem_io.readline) # get the ---
        current_local_gem = local_gem_list.any? ? local_gem_io.readline : nil
        remote_version_io.each_line do |remote_version_line|
          next if remote_version_line.eql?("---\n")
          remote_gem_name = remote_version_line.split[0]
          wrote_local_gem = if local_gem_list.include?(remote_gem_name)
                              if current_local_gem
                                merged_versions_file.write(current_local_gem)
                                true
                              else
                                # no-op, see: https://github.com/rubygems/rubygems.org/issues/3904
                              end
                            elsif current_local_gem && remote_version_line > current_local_gem
                              merged_versions_file.write(current_local_gem)
                              while current_local_gem&.< remote_version_line
                                current_local_gem = advance_local_gem(local_gem_io)
                                merged_versions_file.write(current_local_gem) if current_local_gem&.< remote_version_line
                              end
                              merged_versions_file.write(remote_version_line)
                              false
                            else
                              # if current local gem > remote gem
                              merged_versions_file.write(remote_version_line)
                              false
                            end
          current_local_gem = advance_local_gem(local_gem_io) if wrote_local_gem
        end
        if current_local_gem
          merged_versions_file.write(current_local_gem)
          merged_versions_file.write(local_gem_io.readlines) unless local_gem_io.eof?
        end
        merged_versions_file.flock(File::LOCK_UN)
      end
    end

    def self.advance_local_gem(local_gem_io)
      if !local_gem_io.eof?
        local_gem_io.readline
      else
        nil
      end
    end

    def self.try_load_cached_file(mode = "r")
      block = ->(io) { yield(io); io.close }
      if mode.eql?('w') || File.exist?(merged_versions_path)
        File.open(merged_versions_path, mode, &block)
      else
        StringIO.open("", mode, &block)
      end
    end

    def self.gems_hash(source)
      source[2..-1].each_with_object({}) do |line, hash|
        line.chomp!
        name, versions, digest = line.split
        seen = hash[name]
        if seen
          seen_versions = seen.split[1]
          hash[name] = "#{name} #{seen_versions},#{versions} #{digest}"
        else
          hash[name] = line
        end
      end
    end
  end
end
