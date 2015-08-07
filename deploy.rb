# Change to suit your needs
set :user, 'root'
role :linode, '45.79.4.53'
ssh_options[:port] = 22
ssh_options[:keys] = [File.join(ENV["HOME"], ".ssh/", "id_rsa")]

#Do not change below this line
set :run_method, :sudo
