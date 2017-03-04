#!/usr/bin/env sprinkle -c -s
#/ Usage 
#/
#/ This is how you do things 

$stderr.sync = true

%w(config coturn).each do |lib|
  require_relative lib
end

file = __FILE__
ssh_dir = File.join('/home', "#{USER}", '.ssh')
pub_ssh_key_file = File.join(ENV["HOME"], ".ssh", "id_rsa.pub")
ssh_keys = []

raise "Public SSH key not readable" unless File.readable?(pub_ssh_key_file)

begin
  open(pub_ssh_key_file) { |f|
    f.each_line { |line| 
      ssh_keys.push(line)
    }
  }
rescue
  raise "Unable to open id_rsa.pub"
end

ssh_keys_values = ssh_keys.split

package :install_epel_release do
  yum 'epel-release'
  verify {has_yum 'epel-release'}
end

package :install_fail2ban do
  yum 'fail2ban'
  verify { has_yum 'fail2ban' }
end

package :deploy_user do
  add_user 'deploy'
  verify { has_user 'deploy' } 
end

package :maybe_create_ssh_dir do
  runner "test ! -d #{ssh_dir} && sudo mkdir -p #{ssh_dir}; echo done" do
    post :install, "chown #{USER}:#{USER} #{ssh_dir}", "chmod 700 #{ssh_dir}"
  end
end

package :maybe_touch_authorized_keys do
  requires :maybe_create_ssh_dir
  runner "test ! -f #{ssh_dir}/authorized_keys && touch #{ssh_dir}/authorized_keys; echo done" do
    post :install, "chmod 400 #{ssh_dir}/authorized_keys", "chown #{USER}:#{USER} #{ssh_dir}/authorized_keys"
  end
  verify { has_file "#{ssh_dir}/authorized_keys" }
end

package :deploy_ssh_keys do
  requires :maybe_touch_authorized_keys
  push_text ssh_keys[0], ssh_dir + "/authorized_keys"
  verify { file_contains ssh_dir + "/authorized_keys", ssh_keys_values[2] }
end

package :passwordless_sudo do
#  requires :deploy_user
  @user = USER
  file '/etc/sudoers.d/deploy', :contents => render('deploy.conf') do
    post :install, 'chmod 0400 /etc/sudoers.d/deploy'
  end
  verify { has_file '/etc/sudoers.d/deploy'}
end

package :no_ssh_root_login do
  replace_text 'PermitRootLogin yes', 'PermitRootLogin no', '/etc/ssh/sshd_config'

  verify { file_contains '/etc/ssh/sshd_config', 'PermitRootLogin no'}
end

package :no_ssh_password_login do
  replace_text '^#PasswordAuthentication yes', 'PasswordAuthentication no', '/etc/ssh/sshd_config'

  verify { file_contains '/etc/ssh/sshd_config', 'PasswordAuthentication no'}
end

package :install_logwatch do
  yum 'logwatch'

  verify { has_yum 'logwatch'}
end

package :configure_logwatch_mail do
  requires :install_logwatch
  replace_text '/usr/sbin/logwatch --output mail', "/usr/sbin/logwatch --mailto #{ADMIN_EMAIL} --detail high", '/etc/cron.daily/0logwatch'

  verify { file_contains '/etc/cron.daily/0logwatch', "/usr/sbin/logwatch --mailto #{ADMIN_EMAIL} --detail high"}
end

package :install_iptables_persistent do
  yum 'iptables-persistent'

  verify { has_yum 'iptables-persistent' }
end

package :install_iptables_rules_v4 do
  iptables_dir = '/etc/iptables'
  file '/etc/iptables/rules.v4', :content => File.read('files/iptables.rules.v4') do
    pre :install, "test ! -d #{iptables_dir} && sudo mkdir -p #{iptables_dir}; echo done"
    post :install, "iptables-restore < /etc/iptables/rules.v4"
  end

  verify { has_file '/etc/iptables/rules.v4'}
end

package :install_iptables_rules_v6 do
  iptables_dir = '/etc/iptables'
  file '/etc/iptables/rules.v6', :content => File.read('files/iptables.rules.v6') do
    pre :install, "test ! -d #{iptables_dir} && sudo mkdir -p #{iptables_dir}; echo done"
    post :install, "ip6tables-restore < /etc/iptables/rules.v6"
  end

  verify { has_file '/etc/iptables/rules.v6'}
end

policy :hello_world, :roles => :linode do
  requires :install_epel_release
  requires :install_fail2ban
  requires :deploy_user
  requires :deploy_ssh_keys
  requires :passwordless_sudo
  requires :no_ssh_root_login
#  requires :no_ssh_password_login
  requires :install_logwatch
#  requires :configure_logwatch_mail
#  requires :install_iptables_persistent
  requires :install_iptables_rules_v4
  requires :install_iptables_rules_v6
end

policy :coturn, :roles => :linode do
#  requires :install_coturn
end

deployment do
  delivery :capistrano do
    begin
      recipes 'Capfile'
    rescue LoadError
      recipes 'deploy'
    end    
  end
end
