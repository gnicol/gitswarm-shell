require 'tmpdir'
require 'uri'
require_relative 'config'
require_relative 'utils'

module PerforceSwarm
  module GitFusion
    class RunError < RuntimeError
    end

    class RunAccessError < RunError
    end

    def self.run(id, command, repo: nil, extra: nil, stream_output: nil, for_user: nil, &block)
      # we always log either a debug or error entry; calculate the pre-amble early
      log_commands = [id, command, repo, extra, stream_output, for_user, block].map(&:inspect).join(', ')
      log_context  = "GitFusion.run(#{log_commands}) "

      fail 'run requires a command' unless command
      config = PerforceSwarm::GitlabConfig.new.git_fusion.entry(id)
      url    = PerforceSwarm::GitFusion::URL.new(config['url'])
               .for_user(config.enforce_permissions? ? for_user : nil).command(command).repo(repo).extra(extra)

      Dir.mktmpdir do |temp|
        silenced = false
        output   = ''
        Utils.popen(['git', *git_config_params(config), 'clone', '--', url.to_s], temp) do |line|
          silenced ||= line =~ /^fatal: (repository|Could not read from remote repository\.)/
          next if line =~ /^Warning: Permanently added .* to the list of known hosts/
          next if line =~ /^Cloning into/ || silenced
          output += line
          print line       if stream_output
          block.call(line) if block
        end
        output = validate_git_output(command, output.gsub(/\A\n*|\n*\z/, ''))
        $logger.debug "#{log_context}\n#{output}"
        output
      end
    rescue => e
      $logger.error "#{log_context}\n#{e.inspect}\n#{e.backtrace.join("\n") unless e.is_a?(RunError)}"
      raise PerforceSwarm::GitFusion::RunError, e.message
    end

    def self.validate_git_output(command, output)
      # when a MITM error occurs some platforms still include the command output
      # we want to detect that scenario and fail (even though our output is present)
      # note centos 6.5 seems to have \r\n line endings preventing us from anchoring this regex :(
      mitm_regex = /@ *WARNING: (REMOTE HOST IDENTIFICATION HAS CHANGED!|POSSIBLE DNS SPOOFING DETECTED!) *@/
      fail RunError, output if output =~ mitm_regex

      # command specific validations
      if command == 'list'
        # we're looking for a list of repos, or the message 'no repositories found'
        fail RunError, 'No response was received.' if output.empty?
        valid = output.match(/^no repositories found$/) ||
                output.lines.all? { |line| line.match(/^([^\s]+)\s+(push|pull)?\s+([^\s]+)(\s+(.+?))?$/) }
        fail RunError, output unless valid
      elsif command == 'info'
        # the first line should be boilerplate
        fail RunError, output unless output.start_with?('Perforce - The Fast Software')
      end

      # if no-one got upset, output was ok so return it
      output
    end

    def self.git_config_params(config)
      params = ['core.askpass=' + File.join(__dir__, 'bin', 'git-provide-password'), *config['git_config_params']]
      params.flat_map { |value| ['-c', value] if value && !value.empty? }.compact
    end

    # extends a plain git url with a Git Fusion extended command, optional repo and optional extras
    class URL
      attr_accessor :url, :delimiter
      attr_reader :scheme, :password
      attr_writer :extra, :strip_password, :user, :for_user

      VALID_SCHEMES  = %w(http https ssh)
      VALID_COMMANDS = %w(help info list status wait)

      def initialize(url)
        @strip_password = true
        @user           = nil
        parse(url)
      end

      # parses the given URL, and sets instance variables for base url (without path), command, repo
      # and extra parameters if given - raises an exception if:
      #  * no URL is provided
      #  * an invalid scheme is provided (http, https and ssh are supported)
      #  * missing a username in scp-style urls (e.g. user@host)
      #  * the URL is otherwise invalid, as determined by ruby's URI.parse method
      def parse(url)
        # reset the stored delimiter, command, repo, etc before parsing, in case we're being called multiple times
        self.delimiter = nil
        self.command   = nil
        self.repo      = nil
        self.extra     = nil
        self.for_user  = nil

        fail 'No URL provided.' unless url

        # extract the scheme - no scheme/protocol supplied means it's an scp-style git URL
        %r{^(?<scheme>\w+)://.+$} =~ url
        fail "Invalid URL scheme specified: #{scheme}." unless scheme.nil? || VALID_SCHEMES.index(scheme)

        # explicitly add the scp protocol and fix up the path spec if it uses a colon (needs to be a slash)
        unless scheme
          if %r{^(?<trimmed>([^@]+@)?([^/:]+))(?<delim>[/:])(?<path>.*)$} =~ url
            self.delimiter = delim
            url = trimmed + '/' + path
          else
            self.delimiter = ':'
          end
          url = 'scp://' + url
        end

        # parses a URI object or throws an exception if it's invalid
        parsed = URI.parse(url)

        fail 'User must be specified if scp syntax is used.' if parsed.scheme == 'scp' && !parsed.user
        fail "Invalid URL specified: #{url}." if parsed.host.nil?

        # construct the base URL, grabbing the specified user, if any
        @scheme = parsed.scheme
        if @scheme == 'scp'
          @user    = parsed.user
          self.url = parsed.user + '@' + parsed.host
        else
          self.url  = parsed.scheme + '://' + (parsed.userinfo ? parsed.userinfo + '@' : '') + bare_host(parsed)
          @user     = parsed.user
          @password = parsed.password
        end

        # turf any leading or trailing slashes, and call it a day if there is no remaining path
        path = parsed.path.gsub(%r{^/|/$}, '')
        return if path.empty?

        # the 'foruser' flag can appear anywhere. if present capture and remove it
        # we do this _before_ the path starts_with?@ handling as we may end up removing all @'s
        self.for_user = $~[1] if path.gsub!(/@foruser=([^@]+)/, '')

        # parse out pieces of @-syntax, if present
        if path.start_with?('@')
          # now that we know 'foruser' won't be in the party a simple split suffices for the other bits
          segments     = path[1..-1].split('@', 3)
          self.command = segments[0]
          self.repo    = segments[1]
          self.extra   = segments[2]
        else
          # only repo is specified in this case
          self.repo = path
        end
      rescue URI::Error => e
        raise "Invalid URL specified: #{url} : #{e.message}."
      end

      def self.valid?(url)
        new(url)
        true
      rescue
        return false
      end

      def self.valid_command?(command)
        VALID_COMMANDS.index(command)
      end

      def command=(command)
        fail "Unknown command: #{command}" unless !command || URL.valid_command?(command)
        @command = command
      end

      def command(*args)
        if args.length > 0
          self.command = args[0]
          return self
        end
        @command
      end

      def repo=(repo)
        if repo.is_a? String
          # set the repo to the string given
          @repo = repo
        elsif repo
          # repo is true, throw if we didn't parse a repo from the original URL
          fail 'Repo expected but none given.' unless @repo
        else
          # repo is false, so remove whatever we parsed from the original repo
          @repo = nil
        end
      end

      def repo(*args)
        if args.length > 0
          self.repo = args[0]
          return self
        end
        @repo
      end

      def extra(*args)
        if args.length > 0
          self.extra = args[0]
          return self
        end
        @extra
      end

      def for_user(*args)
        if args.length > 0
          self.for_user = args[0]
          return self
        end
        @for_user
      end

      def strip_password(*args)
        if args.length > 0
          self.strip_password = args[0]
          return self
        end
        @strip_password
      end

      def user(*args)
        if args.length > 0
          self.user = args[0]
          return self
        end
        @user
      end

      def clear_path
        self.repo = nil
        clear_command
        clear_for_user
        self
      end

      def clear_command
        self.command = nil
        self.extra   = nil
        self
      end

      def clear_for_user
        self.for_user = nil
        self
      end

      def to_s
        fail 'Extra requires both command and repo to be specified.' if extra && (!command || !repo)

        # build and put @ and params in the right spots
        str  = build_url
        str += delimiter              if pathed?
        str += '@' + command          if command
        str += '@'                    if command && repo
        str += repo                   if repo
        str += '@' + extra.to_s       if extra
        str += '@foruser=' + for_user if for_user
        str
      end

      def ==(other)
        to_str == other.to_str
      end

      def to_str
        to_s
      end

      def build_url
        if scheme != 'scp'
          # parse and set username/password fields as needed - we've already extracted user/password during init
          parsed          = URI.parse(url)
          parsed.user     = @user
          parsed.password = @password

          # build and include the correct userinfo
          userinfo  = parsed.user ? parsed.user : ''
          userinfo += parsed.password && !strip_password ? ':' + parsed.password : ''
          str       = parsed.scheme + '://' + (!userinfo.empty? ? userinfo + '@' : '') + bare_host(parsed)
        else
          # url is simply user@host
          parsed = url.split('@', 2)
          str    = @user + '@' + parsed[1]
        end
        str
      end

      def delimiter
        @delimiter || '/'
      end

      def pathed?
        command || repo || extra
      end

      def host
        return bare_host(URI.parse(url)) if scheme != 'scp'
        url.split('@', 2)[1]
      end

      protected

      def bare_host(url)
        url.host + (url.port && url.port != url.default_port ? ':' + url.port.to_s : '')
      end
    end
  end
end
