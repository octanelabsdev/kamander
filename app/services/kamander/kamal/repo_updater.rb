module Kamander
  module Kamal
    # Fast-forward only: a clone that can't is reported and left exactly as it is.
    class RepoUpdater
      Result = Data.define(:repo_path, :success, :message) do
        def success? = success

        def summary = "#{File.basename(repo_path)} (#{message.lines.first&.strip})"
      end

      # No prompts, and give up on a stalled network instead of hanging the request.
      GIT_ENV = { "GIT_TERMINAL_PROMPT" => "0", "GIT_SSH_COMMAND" => "ssh -o BatchMode=yes -o ConnectTimeout=10" }.freeze
      GIT_OPTIONS = %w[-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20].freeze

      def initialize(scan_root:)
        @scan_root = scan_root
      end

      def call
        repos = Dir.glob(File.join(@scan_root, "*", ".git")).sort.map { |git_dir| File.dirname(git_dir) }
        repos.map { |repo_path| Thread.new { pull(repo_path) } }.map(&:value)
      end

      private

        def pull(repo_path)
          output, status = Open3.capture2e(GIT_ENV, "git", *GIT_OPTIONS, "-C", repo_path, "pull", "--ff-only", "--quiet")
          Result.new(repo_path: repo_path, success: status.success?, message: output.strip)
        rescue SystemCallError => e
          Result.new(repo_path: repo_path, success: false, message: e.message)
        end
    end
  end
end
