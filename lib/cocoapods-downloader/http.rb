require 'cocoapods-downloader/remote_file'

module Pod
  module Downloader
    class Http < RemoteFile
      USER_AGENT_HEADER = 'User-Agent'.freeze

      private

      executable :curl

      def canRedownload 
        return false unless @url.start_with?("https://github.com/")
        return true
      end

      def download_file(full_filename)
        save_log "-----------------"
        parameters = ['-f', '-L', '-o', full_filename, url, '--create-dirs', '--netrc-optional', '--retry', '2']
        parameters << user_agent_argument if headers.nil? ||
            headers.none? { |header| header.casecmp(USER_AGENT_HEADER).zero? }

        headers.each do |h|
          parameters << '-H'
          parameters << h
        end unless headers.nil?

        begin
          save_log "curl download #{@url}"
          curl! parameters
        rescue DownloaderError => e
          if canRedownload
            @url.sub! "https://github.com/", "https://ghproxy.com/https://github.com/"
            save_log "curl download redownload #{@url}"
            download_file(full_filename)
          else
            save_log "curl download failed #{@url}"
            raise
          end
        end
        save_log "curl download succed #{@url}"
      end

      def save_log message
        `echo "#{Time.now} - #{message}" >> ~/cocoapods_log`
      end

      # Returns a cURL command flag to add the CocoaPods User-Agent.
      #
      # @return [String] cURL command -A flag and User-Agent.
      #
      def user_agent_argument
        "-A '#{Http.user_agent_string}'"
      end
    end
  end
end
