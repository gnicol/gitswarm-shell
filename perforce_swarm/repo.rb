require_relative '../lib/gitlab_init'
require_relative 'utils'
require_relative 'git_fusion'
require_relative 'git_fusion_repo'

module PerforceSwarm
  class Repo
    attr_accessor :path

    def initialize(path)
      path = File.realpath(path)
      fail 'Not a valid repo path' unless File.exist?(File.join(path, 'config'))
      @path = path
    end

    def mirrored?
      return false unless mirror_url
      true
    end

    # update/delete the mirror remote url on the repo
    # if url is nil, the mirror remote will be deleted
    def mirror_url=(url)
      # construct the Git Fusion URL based on the mirror URL given
      # run the git command to add the remote
      resolved_url = GitFusionRepo.resolve_url(url.to_s)

      # remove the mirror remote, and exit if we were given nil, false or empty string
      @mirror_url = nil
      Utils.popen(%w(git remote remove mirror), @path)
      return url if !url || (url.is_a?(String) && url.empty?)

      # add/update the mirror remote
      output, status = Utils.popen(['git', 'remote', 'add', 'mirror', resolved_url], @path)
      unless status.zero? && mirror_url == resolved_url
        fail "Failed to add mirror remote #{url} to #{@path} its still #{mirror_url}\n#{output}"
      end

      url
    end

    def mirror_head
      config            = PerforceSwarm::GitlabConfig.new.git_fusion.entry_by_url(mirror_url)
      git_config_params = PerforceSwarm::GitFusion.git_config_params(config)
      output, status    = Utils.popen(['git', *git_config_params, 'remote', 'show', 'mirror'], @path)

      fail "Failed to query mirror remote for #{@path} its head\n#{output}" unless status.zero?

      head = output[/^\s+HEAD branch:\s+(\S+)/, 1]

      # Ensure HEAD points to a known branch before we return it.
      # Empty repos will report (unknown) for example as their head
      if head
        output, _status = Utils.popen(['git', 'branch', '--list', head], @path)
        return nil unless output && !output.empty?
      end

      head
    end

    def mirror_url
      return @mirror_url if @mirror_url

      @mirror_url, status = Utils.popen(%w(git config --get remote.mirror.url), @path)
      @mirror_url.strip!
      @mirror_url = false unless status.zero? && !@mirror_url.empty?
      @mirror_url
    end

    def mirror_url_object
      GitFusion::URL.new(mirror_url)
    end
  end
end
