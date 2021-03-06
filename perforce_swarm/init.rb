require_relative 'config'
require_relative 'mirror'
require_relative '../lib/gitlab_custom_hook'
require_relative '../lib/gitlab_shell'
require_relative '../lib/gitlab_projects'

module PerforceSwarm
  # If everything else looks good, we want to do a mirror
  # push as the last step in the pre-recieve hook
  module GitlabCustomHookExtension
    def pre_receive(changes, repo_path)
      # run our update hook first, since if any of them fail, the whole operation does;
      # this is the same logic that occurs in "git push --atomic"
      changes.split(/\r\n|\r|\n/).each do |line|
        # run the actual update hook, bailing on the first unsuccessful one (if any)
        $logger.debug('Running PerforceSwarm custom hook update')
        old_value, new_value, ref_name = line.strip.split
        return false unless orig_update(ref_name, old_value, new_value, repo_path)
      end

      # continue running the pre-receive hook
      $logger.debug 'Running PerforceSwarm custom hook pre_receive'
      return false unless super

      # Transform the changes into an array of pushable ref updates
      refs = []
      changes.split(/\r\n|\r|\n/).each do |refline|
        _src, tgt, ref = refline.strip.split
        refspec = (tgt.match(/^0+$/) ? '' : tgt) + ':' + ref
        refs.push(refspec)
      end
      Mirror.push(refs, repo_path, receive_pack: true)
      true
    rescue Mirror::Exception
      return false
    end

    # override the update hook to always be happy, since we've already called the
    # *actual* update hook in pre-receive
    def update(_ref_name, _old_value, _new_value, _repo_path)
      true
    end

    def post_receive(changes, repo_path, options = {})
      $logger.debug 'Running PerforceSwarm custom hook post_receive'

      options = { receive_pack: true }.merge(options)
      # if this repo is mirroring, UNLOCK as we know refs have been updated at this point
      Mirror.lock_socket('UNLOCK') if options[:receive_pack] && Repo.new(repo_path).mirrored?
      super(changes, repo_path)
    end
  end

  module GitlabNetExtension
    def request(method, url, params = {})
      response = super

      # Custom error handling for 400 errors for ssh on /allowed, because GitLab's
      # error handling doesn't make it back to the client properly
      if response.code == '400' && ENV['SSH_ORIGINAL_COMMAND'] && url =~ /\/allowed$/
        puts "#{format('%04x', response.body.bytesize + 8)}ERR #{response.body}"
      end

      response
    end
  end

  # For ssh, do an early fetch from mirror to
  # make sure all the refs are up-to-date
  module GitlabShellExtension
    def process_cmd(args)
      repo_full_path = File.join(repos_path, repo_name)

      # push errors are fatal but pull errors are ignorable
      if @git_cmd == 'git-receive-pack'
        Mirror.fetch!(repo_full_path)
      else
        Mirror.fetch(repo_full_path)
      end

      super
    rescue Mirror::Exception => e
      unless @git_cmd == 'git-receive-pack'
        puts "#{format('%04x', e.message.bytesize + 8)}ERR #{e.message}"
      end
      raise Mirror::Exception, e.message
    end

    def exec_cmd(*args)
      if args[0] == 'git-receive-pack'
        args[0] = File.join(ROOT_PATH, 'perforce_swarm', 'bin', 'swarm-receive-pack')
      end
      super(*args)
    end
  end

  module GitlabProjectsExtension
    def create_branch
      branch_name = ARGV[0]
      ref         = ARGV[1] || 'HEAD'
      result = false
      Mirror.push(["#{ref}:#{branch_name}"], full_path) { result = super }
      result
    rescue Mirror::Exception
      return false
    end

    def rm_branch
      result = false
      Mirror.push([":#{ARGV.first}"], full_path) { result = super }
      result
    rescue Mirror::Exception
      return false
    end

    def fork_project
      # ensure the namespace directory exists
      new_namespace = ARGV[0]
      if new_namespace
        namespaced_path = File.join(repos_path, new_namespace)
        FileUtils.mkdir_p(namespaced_path, mode: 0770) unless File.exist?(namespaced_path)
      end
      super
    end
  end
end

class GitlabCustomHook
  alias_method :orig_update, :update
  prepend PerforceSwarm::GitlabCustomHookExtension
end

class GitlabNet
  prepend PerforceSwarm::GitlabNetExtension
end

class GitlabShell
  prepend PerforceSwarm::GitlabShellExtension
end

class GitlabProjects
  prepend PerforceSwarm::GitlabProjectsExtension
end
