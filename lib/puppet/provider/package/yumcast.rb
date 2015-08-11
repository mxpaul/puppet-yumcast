require 'puppet/util/package'

Puppet::Type.type(:package).provide :yumcast, :parent => :yum, :source => :yum do
  desc "Support (custom) via `yum`.

  Using this provider's `uninstallable` feature will not remove dependent packages. To
  remove dependent packages with this provider use the `purgeable` feature, but note this
  feature is destructive and should be used with the utmost care."

  has_feature :versionable

  commands :yum => "yum", :rpm => "rpm", :python => "python", :repoquery => "repoquery"

  attr_accessor :latest_info

  if command('rpm')
    confine :true => begin
      rpm('--version')
      rescue Puppet::ExecutionFailure
        false
      else
        true
      end
  end

  #defaultfor :operatingsystem => [:fedora, :centos, :redhat]

  def install
    should = @resource.should(:ensure)
    self.debug "Ensuring => #{should}"
    wanted = @resource[:name]
    operation = :install

    case should
    when :latest
      #require 'pp'
      #pp( self.instance_variables) 
      should = self.latest
      # Add the package version
      wanted += "-#{should}"
      is = self.query
      if is && Puppet::Util::Package.versioncmp(should, is[:ensure]) < 0
        self.debug "Downgrading package #{@resource[:name]} from version #{is[:ensure]} to #{should}"
        operation = :downgrade
      end
    when true, false, Symbol
      # pass
      should = nil
    else
      # Add the package version
      wanted += "-#{should}"
      is = self.query
      if is && Puppet::Util::Package.versioncmp(should, is[:ensure]) < 0
        self.debug "Downgrading package #{@resource[:name]} from version #{is[:ensure]} to #{should}"
        operation = :downgrade
      end
    end

    yum "-d", "0", "-e", "0", "-y", operation, wanted

    is = self.query
    raise Puppet::Error, "Could not find package #{self.name}" unless is

    # FIXME: Should we raise an exception even if should == :latest
    # and yum updated us to a version other than @param_hash[:ensure] ?
    raise Puppet::Error, "Failed to update to version #{should}, got version #{is[:ensure]} instead" if should && should != is[:ensure]
  end

  # What's the latest package version available?
  def latest
    upd = latest_info
    unless upd.nil?
      # FIXME: there could be more than one update for a package
      # because of multiarch
      return "#{upd[:epoch]}:#{upd[:version]}-#{upd[:release]}"
    else
      # Yum didn't find updates
      raise Puppet::DevError, "Tried to get latest on a missing package" if properties[:ensure] == :absent
      lastver = (repoquery '--qf=%{name} %{epoch} %{version} %{release} %{arch}', @resource[:name]).chomp!
      verhash = self.class.nevra_to_hash(lastver)
      self.debug('end latest')
      return verhash[:ensure] if lastver.length
      # We probably never get here
      return properties[:ensure]
    end
  end

end
