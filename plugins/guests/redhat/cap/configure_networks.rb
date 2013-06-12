require "set"
require "tempfile"

require "vagrant/util/retryable"
require "vagrant/util/template_renderer"

module VagrantPlugins
  module GuestRedHat
    module Cap
      class ConfigureNetworks
        extend Vagrant::Util::Retryable
        include Vagrant::Util

        def self.configure_networks(machine, networks)
          network_scripts_dir = machine.guest.capability("network_scripts_dir")
	  
          networks.each do |network|
			retryable(:on => Vagrant::Errors::VagrantError, :tries => 3, :sleep => 2) do
              machine.communicate.sudo("/sbin/ifdown eth#{network[:interface]} 2> /dev/null", :error_check => false)
			end
			
            # Remove any previous vagrant configuration in this network interface's
            # configuration files.
            machine.communicate.sudo("touch #{network_scripts_dir}/ifcfg-eth#{network[:interface]}")
            machine.communicate.sudo("sed -e '/^#VAGRANT-BEGIN/,/^#VAGRANT-END/ d' #{network_scripts_dir}/ifcfg-eth#{network[:interface]} > /tmp/vagrant-ifcfg-eth#{network[:interface]}")
            machine.communicate.sudo("cat /tmp/vagrant-ifcfg-eth#{network[:interface]} > #{network_scripts_dir}/ifcfg-eth#{network[:interface]}")
            machine.communicate.sudo("rm /tmp/vagrant-ifcfg-eth#{network[:interface]}")

			# Render and upload the network entry file to a deterministic
            # temporary location.
            entry = TemplateRenderer.render("guests/redhat/network_#{network[:type]}",
                                            :options => network)

            temp = Tempfile.new("vagrant")
            temp.binmode
            temp.write(entry)
            temp.close

            machine.communicate.upload(temp.path, "/tmp/vagrant-network-entry_#{network[:interface]}")

            machine.communicate.sudo("cat /tmp/vagrant-network-entry_#{network[:interface]} >> #{network_scripts_dir}/ifcfg-eth#{network[:interface]}")

			retryable(:on => Vagrant::Errors::VagrantError, :tries => 3, :sleep => 2) do
              machine.communicate.sudo("/sbin/ifup eth#{network[:interface]} 2> /dev/null", :error_check => false)
			end

            machine.communicate.sudo("rm /tmp/vagrant-network-entry_#{network[:interface]}")
          end
        end
      end
    end
  end
end
