module Kamander
  module Ci
    # The commit remote-ci would run in a local repo: its HEAD and branch.
    Checkout = Data.define(:sha, :branch) do
      def self.read(repo_path)
        sha = git(repo_path, "rev-parse", "HEAD") or return
        new(sha: sha, branch: git(repo_path, "rev-parse", "--abbrev-ref", "HEAD"))
      end

      def self.git(repo_path, *args)
        out, status = Open3.capture2("git", "-C", repo_path, *args, err: File::NULL)
        out.strip if status.success?
      rescue SystemCallError
        nil
      end

      def short_sha = sha.first(7)
    end
  end
end
