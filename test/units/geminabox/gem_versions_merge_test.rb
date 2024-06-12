require_relative '../../test_helper'

module Geminabox
  class GemVersionsMergeTest < Minitest::Test

    def test_merge_local_over_remote
      local = "created_at: 2021-07-27T16:14:36.466+0000\n---\ntest-gem 0.0.1 91643f56b430feed3f6725c91fcfac70\n"
      remote = "created_at: 2021-07-27T16:14:36.466+0000\n---\ntest-gem 0.0.5 e7218e76477e2137355d2e7ded094925\n"
      File.write(GemVersionsMerge.proxy_versions_path, remote)
      expected = local
      assert_equal expected, GemVersionsMerge.merge(local)
    end

    def test_timestamp_local_over_remote
      local = "created_at: 2021-06-27T16:14:36.466+0000\n---\ntest-gem 0.0.1 91643f56b430feed3f6725c91fcfac70\n"
      remote = "created_at: 2020-06-27T16:14:36.466+0000\n---\ntest-gem 0.0.5 e7218e76477e2137355d2e7ded094925\n"
      File.write(GemVersionsMerge.proxy_versions_path, remote)
      expected = local[/created_at:\s(\S+)\s/]
      timestamp = GemVersionsMerge.merge(local)[/created_at:\s(\S+)\s/]
      assert_equal expected, timestamp
    end

    def test_merge_multiple_local_over_remote
      local = "created_at: 2021-06-27T16:14:36.466+0000\n---\ntest-gem1 0.0.1 91643f56b430feed3f6725c91fcfac70\ntest-gem2 0.0.1 75f21fffe3703239725b848bf82d3143\n"
      remote = "created_at: 2021-06-27T16:14:36.466+0000\n---\ntest-gem2 0.0.2 c379eb80dd9b53e8b99e5507c8aebcb0\ntest-gem3 0.0.1 4e58bc03e301f704950410b713c20b69\ntest-gem4 0.0.1 e00c558565f7b03a438fbd93d854b7de\n"
      File.write(GemVersionsMerge.proxy_versions_path, remote)
      merged = GemVersionsMerge.merge(local)
      expected = "created_at: 2021-06-27T16:14:36.466+0000\n---\n" \
                 "test-gem1 0.0.1 91643f56b430feed3f6725c91fcfac70\n" \
                 "test-gem2 0.0.1 75f21fffe3703239725b848bf82d3143\n" \
                 "test-gem3 0.0.1 4e58bc03e301f704950410b713c20b69\n" \
                 "test-gem4 0.0.1 e00c558565f7b03a438fbd93d854b7de\n"
      assert_equal expected, merged
    end

    def test_merge_multiple_remote_version_entries_are_merged
      local = "created_at: 2021-06-27T16:14:36.466+0000\n---\ntest-gem1 0.0.1 91643f56b430feed3f6725c91fcfac70\ntest-gem2 0.0.1 75f21fffe3703239725b848bf82d3143\ntest-gem4 0.0.1 75f21fffe3703239725b848bf82d3143\n"
      remote = "created_at: 2021-06-27T16:14:36.466+0000\n---\ntest-gem3 0.0.1,0.0.2 c379eb80dd9b53e8b99e5507c8aebcb0\ntest-gem3 1.0.0 4e58bc03e301f704950410b713c20b69\n"
      File.write(GemVersionsMerge.proxy_versions_path, remote)
      merged = GemVersionsMerge.merge(local)
      expected = "created_at: 2021-06-27T16:14:36.466+0000\n---\n" \
                 "test-gem1 0.0.1 91643f56b430feed3f6725c91fcfac70\n" \
                 "test-gem2 0.0.1 75f21fffe3703239725b848bf82d3143\n" \
                 "test-gem3 0.0.1,0.0.2 c379eb80dd9b53e8b99e5507c8aebcb0\n" \
                 "test-gem3 1.0.0 4e58bc03e301f704950410b713c20b69\n" \
                 "test-gem4 0.0.1 75f21fffe3703239725b848bf82d3143\n"
      assert_equal expected, merged
    end

    def test_file_merge
      local = "created_at: 2021-06-27T16:14:36.466+0000\n---\ntest-gem1 0.0.1 91643f56b430feed3f6725c91fcfac70\ntest-gem2 0.0.1 75f21fffe3703239725b848bf82d3143\n"
      remote = "created_at: 2021-06-27T16:14:36.466+0000\n---\ntest-gem2 1.0.0 4e58bc03e301f704950410b713c20b69\ntest-gem3 0.0.1,0.0.2 c379eb80dd9b53e8b99e5507c8aebcb0\ntest-gem2 1.0.0 4e58bc03e301f704950410b713c20b69\ntest-gem2 1.0.0 4e58bc03e301f704950410b713c20b69\ntest-gem2 1.0.0 4e58bc03e301f704950410b713c20b69\ntest-gem2 1.0.0 4e58bc03e301f704950410b713c20b69\ntest-gem3 1.1.1 4e58bc03e301f704950410b713c20b69\n"
      expected = <<~HEREDOC
        created_at: 2021-06-27T16:14:36.466+0000
        ---
        test-gem1 0.0.1 91643f56b430feed3f6725c91fcfac70
        test-gem2 0.0.1 75f21fffe3703239725b848bf82d3143
        test-gem3 0.0.1,0.0.2 c379eb80dd9b53e8b99e5507c8aebcb0
        test-gem3 1.1.1 4e58bc03e301f704950410b713c20b69
      HEREDOC
      StringIO.open(local) do |local_versions_file|
        StringIO.open(remote) do |remote_versions_file|
          remote_preamble = remote_versions_file.readline
          local_preamble = local_versions_file.readline
          remote_time = Time.parse(remote_preamble.split[1])
          local_time = Time.parse(local_preamble.split[1])
          preamble = (local_time > remote_time ? remote_preamble : local_preamble)
          GemVersionsMerge.write_version_entries(preamble, local_versions_file, remote_versions_file)
        end
      end

      result = File.read(GemVersionsMerge.merged_versions_path)
      assert_equal(expected, result)
    end

  end
end
