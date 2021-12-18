# frozen_string_literal: true

module Bundler
  #
  # This class handles installing and switching to the version of bundler needed
  # by an application.
  #
  class SelfManager
    def restart_with_locked_bundler_if_needed
      return unless needs_switching? && installed?

      restart_with(lockfile_version)
    end

    def install_locked_bundler_and_restart_with_it_if_needed
      return unless needs_switching?

      Bundler.ui.info \
        "Bundler #{current_version} is running, but your lockfile was generated with #{lockfile_version}. " \
        "Installing Bundler #{lockfile_version} and restarting using that version."

      install_and_restart_with(lockfile_version)
    end

    def update_bundler_and_restart_with_it_if_needed(target)
      version = resolve_update_version_from(target)
      return unless version

      Bundler.ui.info "Updating bundler to #{version}."

      install_and_restart_with(version)
    end

    private

    def install_and_restart_with(version)
      install(version)
    rescue StandardError => e
      Bundler.ui.trace e
      Bundler.ui.warn "There was an error installing the locked bundler version (#{lockfile_version}), rerun with the `--verbose` flag for more details. Going on using bundler #{current_version}."
    else
      restart_with(version)
    end

    def install(version)
      bundler_dep = Gem::Dependency.new("bundler", version)

      Gem.install(bundler_dep)
    end

    def restart_with(version)
      configured_gem_home = ENV["GEM_HOME"]
      configured_gem_path = ENV["GEM_PATH"]

      Bundler.with_original_env do
        Kernel.exec(
          { "GEM_HOME" => configured_gem_home, "GEM_PATH" => configured_gem_path, "BUNDLER_VERSION" => version },
          $PROGRAM_NAME, *ARGV
        )
      end
    end

    def needs_switching?
      ENV["BUNDLER_VERSION"].nil? &&
        Bundler.rubygems.supports_bundler_trampolining? &&
        SharedHelpers.in_bundle? &&
        lockfile_version &&
        released?(lockfile_version) &&
        !running?(lockfile_version)
    end

    def resolve_update_version_from(target)
      return if versions.empty?

      requirement = Gem::Requirement.new(target)
      resolved_version = versions.reverse.find {|v| requirement.satisfied_by?(v) }
      needs_update = requirement.specific? ? !running?(resolved_version) : running_older_than?(resolved_version)
      resolved_version = resolved_version.to_s

      return unless released?(resolved_version) && needs_update

      resolved_version
    end

    def versions
      @versions ||= Fetcher.new(Source::Rubygems::Remote.new(Bundler::URI("https://rubygems.org"))).versions("bundler")
    end

    def running?(version)
      version == current_version
    end

    def running_older_than?(version)
      current_version < version
    end

    def released?(version)
      !version.end_with?(".dev")
    end

    def installed?
      Bundler.configure

      Bundler.rubygems.find_bundler(lockfile_version)
    end

    def current_version
      @current_version ||= Gem::Version.new(Bundler::VERSION)
    end

    def lockfile_version
      @lockfile_version ||= Bundler::LockfileParser.bundled_with
    end
  end
end
