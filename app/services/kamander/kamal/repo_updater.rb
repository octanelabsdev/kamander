module Kamander
  module Kamal
    # Fast-forwards each git repo under the scan root, so a host that keeps its
    # own clones (a shared box) reads current deploy config. Never merges or resets:
    # a clone that can't fast-forward is reported and left as it is.
    class RepoUpdater
      Result = Data.define(:repo_path, :success, :message) do
        def success? = success
      end

      # No prompts, and give up on a stalled network instead of hanging the request.
      GIT_ENV = { "GIT_TERMINAL_PROMPT" => "0", "GIT_SSH_COMMAND" => "ssh -o BatchMode=yes -o ConnectTimeout=10" }.freeze
      GIT_OPTIONS = %w[-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20].freeze

      def initialize(scan_root:)
        @scan_root = scan_root
      end

      def call
        Dir.glob(File.join(@scan_root, "*", ".git")).sort.map { |git_dir| pull(File.dirname(git_dir)) }
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
