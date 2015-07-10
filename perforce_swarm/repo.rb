require_relative '../lib/gitlab_init'
require_relative 'utils'

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

    def mirror_url=(url)
      # construct the Git Fusion URL based on the mirror URL given
      # run the git command to add the remote
      resolved_url = GitFusionRepo.resolve_url(url)
      Utils.popen(%w(git remote remove mirror), @path)
      output, status = Utils.popen(['git', 'remote', 'add', 'mirror', resolved_url], @path)
      @mirror_url    = nil
      unless status.zero? && mirror_url == resolved_url
        fail "Failed to add mirror remote #{url} to #{@path} its still #{mirror_url}\n#{output}"
      end

      url
    end

    def mirror_url
      return @mirror_url if @mirror_url

      @mirror_url, status = Utils.popen(%w(git config --get remote.mirror.url), @path)
      @mirror_url.strip!
      @mirror_url = false unless status.zero? && !@mirror_url.empty?
      @mirror_url
    end
  end
end
