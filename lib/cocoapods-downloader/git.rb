module Pod
  module Downloader
    # Concreted Downloader class that provides support for specifications with
    # git sources.
    #
    class Git < Base
      def self.options
        [:commit, :tag, :branch, :submodules]
      end

      def options_specific?
        !(options[:commit] || options[:tag]).nil?
      end

      def checkout_options
        options = {}
        options[:git] = url
        options[:commit] = target_git('rev-parse', 'HEAD').chomp
        options[:submodules] = true if self.options[:submodules]
        options
      end

      def self.preprocess_options(options)
        return options unless options[:branch]

        command = ['ls-remote',
                   options[:git],
                   options[:branch]]
        output = Git.execute_command('git', command)
        match = commit_from_ls_remote output, options[:branch]

        return options if match.nil?

        options[:commit] = match
        options.delete(:branch)

        options
      end

      # Matches a commit from the branches reported by git ls-remote.
      #
      # @note   When there is a branch and tag with the same name, it will match
      #         the branch, since `refs/heads` is sorted before `refs/tags`.
      #
      # @param  [String] output
      #         The output from git ls-remote.
      #
      # @param  [String] branch_name
      #         The desired branch to match a commit to.
      #
      # @return [String] commit hash string, or nil if no match found
      #
      def self.commit_from_ls_remote(output, branch_name)
        return nil if branch_name.nil?
        encoded_branch_name = branch_name.dup.force_encoding(Encoding::ASCII_8BIT)
        match = %r{([a-z0-9]*)\trefs\/(heads|tags)\/#{Regexp.quote(encoded_branch_name)}}.match(output)
        match[1] unless match.nil?
      end

      private_class_method :commit_from_ls_remote

      private

      # @!group Base class hooks

      def download!
        clone
        checkout_commit if options[:commit]
      end

      # @return [void] Checks out the HEAD of the git source in the destination
      #         path.
      #
      def download_head!
        clone(true)
      end

      def canRedownload 
        return true if @url.start_with?("https://github.com/")
        return true if @url == "https://chromium.googlesource.com/webm/libwebp"
        return false
      end

      # @!group Download implementations

      executable :git

      # Clones the repo. If possible the repo will be shallowly cloned.
      #
      # @note   The `:commit` option requires a specific strategy as it is not
      #         possible to specify the commit to the `clone` command.
      #
      # @note   `--branch` command line option can also take tags and detaches
      #         the HEAD.
      #
      # @param  [Bool] force_head
      #         If any specific option should be ignored and the HEAD of the
      #         repo should be cloned.
      #
      # @param  [Bool] shallow_clone
      #         Whether a shallow clone of the repo should be attempted, if
      #         possible given the specified {#options}.
      #
      def clone(force_head = false, shallow_clone = true)
        save_log "-----------------"
        ui_sub_action('Git download') do
          begin
            save_log "git clone #{@url}"
            `rm -rf #{target_path}`
            git! clone_arguments(force_head, shallow_clone)
            update_submodules
          rescue DownloaderError => e
            if e.message =~ /^fatal:.*does not support (--depth|shallow capabilities)$/im
              clone(force_head, false)
            elsif canRedownload
              @url = "https://github.com/webmproject/libwebp.git" if @url == "https://chromium.googlesource.com/webm/libwebp"
              @url.sub! "https://github.com/", "https://ghproxy.com/https://github.com/" if @url.start_with?("https://github.com/")
              save_log "git clone redownload #{@url}"
              clone
            else
              save_log "git clone failed #{@url}"
              raise
            end
          end
        end
        save_log "git clone succed #{@url}"
      end

      def save_log message
        `echo "#{Time.now} - #{message}" >> ~/cocoapods_log`
      end

      def update_submodules
        return initsubmodule(target_path, "https://github.com/", "https://ghproxy.com/https://github.com/") if @url.start_with?("https://ghproxy.com/https://github.com/")
        return unless options[:submodules]
        target_git %w(submodule update --init --recursive)
      end


      def initsubmodule(path, url, replaceurl)
        path = "#{path}"
        require 'rugged'
        path = path.chop if path.end_with?("/")
    
        repo = Rugged::Repository.new(path)
        return if repo.nil? || repo.empty?
        return if repo.submodules.count < 1
    
        for submodule in repo.submodules
          repo.submodules.update(submodule.name, {:url => submodule.url.gsub!(url, replaceurl)})
        end
    
        `git -C #{path} submodule update --init`
    
        for submodule in repo.submodules
          submodulePath = path + "/" + submodule.path
          initsubmodule(submodulePath, url, replaceurl)
        end
      end


      # The arguments to pass to `git` to clone the repo.
      #
      # @param  [Bool] force_head
      #         If any specific option should be ignored and the HEAD of the
      #         repo should be cloned.
      #
      # @param  [Bool] shallow_clone
      #         Whether a shallow clone of the repo should be attempted, if
      #         possible given the specified {#options}.
      #
      # @return [Array<String>] arguments to pass to `git` to clone the repo.
      #
      def clone_arguments(force_head, shallow_clone)
        command = ['clone', url, target_path, '--template=']

        if shallow_clone && !options[:commit]
          command += %w(--single-branch --depth 1)
        end

        unless force_head
          if tag_or_branch = options[:tag] || options[:branch]
            command += ['--branch', tag_or_branch]
          end
        end

        command
      end

      # Checks out a specific commit of the cloned repo.
      #
      def checkout_commit
        target_git 'checkout', '--quiet', options[:commit]
        update_submodules
      end

      def target_git(*args)
        git!(['-C', target_path] + args)
      end
    end
  end
end
