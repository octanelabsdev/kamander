require "test_helper"

class Kamander::Kamal::RepoUpdaterTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir
    @origin = File.join(@root, "origin.git")
    @scan_root = File.join(@root, "repos")
    git @root, "init", "-q", "--bare", "-b", "main", @origin
    seed = File.join(@root, "seed")
    git @root, "clone", "-q", @origin, seed
    commit seed, "first"
    git seed, "push", "-q", "origin", "HEAD:main"
    FileUtils.mkdir_p(@scan_root)
    git @scan_root, "clone", "-q", @origin, "app"
    @seed = seed
    @clone = File.join(@scan_root, "app")
  end

  teardown { FileUtils.remove_entry(@root) }

  test "each clone under the scan root fast-forwards to its upstream" do
    commit @seed, "second"
    git @seed, "push", "-q", "origin", "HEAD:main"

    results = Kamander::Kamal::RepoUpdater.new(scan_root: @scan_root).call

    assert results.sole.success?, results.sole.message
    assert_equal head(@seed), head(@clone)
  end

  test "a clone that diverged is left alone and the failure names it" do
    commit @seed, "remote change"
    git @seed, "push", "-q", "origin", "HEAD:main"
    commit @clone, "local change"
    before = head(@clone)

    result = Kamander::Kamal::RepoUpdater.new(scan_root: @scan_root).call.sole

    assert_not result.success?
    assert_equal @clone, result.repo_path
    assert_match(/fast-forward|diverg/i, result.message)
    assert_equal before, head(@clone), "the clone must not be merged or reset"
  end

  test "folders that aren't git repos are skipped" do
    FileUtils.mkdir_p(File.join(@scan_root, "notes"))

    assert_equal [ @clone ], Kamander::Kamal::RepoUpdater.new(scan_root: @scan_root).call.map(&:repo_path)
  end

  private

    def git(dir, *args)
      _out, err, status = Open3.capture3("git", "-c", "user.name=t", "-c", "user.email=t@example.com", *args, chdir: dir)
      assert status.success?, "git #{args.join(" ")}: #{err}"
    end

    def commit(dir, message) = git(dir, "commit", "-q", "--allow-empty", "-m", message)

    def head(dir) = Open3.capture2("git", "-C", dir, "rev-parse", "HEAD").first.strip
end
