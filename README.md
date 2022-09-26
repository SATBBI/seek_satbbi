# SEEK Ansible

Ansible script to install SEEK and all its dependencies.

Tested on fresh ubuntu install. 


## Host, user and password set up

Set the host ip address in the *hosts* file.

Set the username (***user_var***) in the *group_vars/vars.yml* file.

Adjust the destination (***git_dest***) for the SEEK folder that will be generated in the *group_vars/vars.yml* file.

Set the ***local_vm_become_password*** variable in the *group_vars/sensitive_vars.yml* file, preferably encrypted (see [Ansible vault](https://docs.ansible.com/ansible/2.8/user_guide/vault.html#variable-level-encryption)). In summary:

 - Create a file *.vault-password.ignore* with the encryption password.
 - Create a file *group_vars/sensitive_vars.yml.ignore* with your passwords in plain text. 
    -- Note: If you choose a different name, update the *ansible.cfg* file.
 - Encrypt your variables by running ```ansible-vault encrypt group_vars/sensitive_vars.yml.ignore --output group_vars/sensitive_vars.yml```.


Install SEEK and all its dependencies by running
```
ansible-playbook Deploy-SEEK.yml
```



## Further configuration
The current version does not generate the docs for Ruby 2.7.5, you may want to do so by running
```
rvm docs generate-ri
```
