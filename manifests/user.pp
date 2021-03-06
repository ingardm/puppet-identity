# == Defined Type: user
#
# Manages a user and his primary group
#
# === Parameters
#
# [*ensure*]
#   Default: present
#
# [*comment*]
#   Default: ''. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-comment
#
# [*uid*]
#   Default: undef. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-uid
#
# [*gid*]
#   Default: $uid. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-gid
#
# [*groups*]
#   Default: []. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-groups
#
# [*password*]
#   Default: undef. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-password
#
# [*ssh_keys*]
#   Default: {}. A hash of SSH public keys which are assiciated with this user account.
#   The hash is passed to the create_resources function to create `ssh_authorized_key` resources.
#
# [*purge_ssh_keys*]
#   Default: true. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-purge_ssh_keys
#
# [*manage_home*]
#   Default: true. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-managehome
#   It also removes the homedirectory if the parameter ensure is set to absent.
#
# [*home*]
#   Default: /home/$username. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-home
#
# [*home_perms_recursive*]
#   Default: false. Manage home folder permissions recursively.
#
# [*home_perms*]
#   Default: 0755. Home folder permissions
#
# [*system*]
#   Default: false. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-system
#
# [*shell*]
#   Default: /bin/bash. See https://docs.puppetlabs.com/references/latest/type.html#user-attribute-shell
#
# [*ignore_uid_gid*]
#   Default: false. If set to true, the uid and gid parameters are ignored and always set to undef.
#
# [*manage_dotfiles*]
#   Default: false. When true, then deliver some dotfiles found in identity::dotfiles_source/$username
#   to the users home directory. They won't be purged if they are not there.
#
# [*manage_group*]
#   Default: true. When true, then a group will be created with the same name as the user. If false
#   the group will not be created and gid has to be set.
#
define identity::user (
  $ensure               = present,
  $comment              = '',
  $uid                  = undef,
  $gid                  = undef,
  $groups               = [],
  $password             = undef,
  $ssh_keys             = {},
  $purge_ssh_keys       = true,
  $manage_home          = true,
  $home                 = undef,
  $home_perms_recursive = false,
  $home_perms           = undef,
  $system               = false,
  $shell                = '/bin/bash',
  $ignore_uid_gid       = false,
  $manage_dotfiles      = false,
  $manage_group         = true,
) {

  include ::identity

  # Input validation
  validate_string($comment)
  validate_array($groups)
  validate_hash($ssh_keys)
  validate_bool($purge_ssh_keys)
  validate_bool($manage_home)
  validate_bool($system)
  validate_absolute_path($shell)
  validate_bool($ignore_uid_gid)
  validate_bool($manage_dotfiles)
  validate_bool($manage_group)

  # Check if gid is set when manage_group is false
  unless $manage_group {
    unless $gid {
      fail('If group is not managed, the gid has to be set')
    }
  }

  # Variable collection
  $username = $title
  $home_dir = $home ? {
    undef   => "/home/${username}",
    default => $home,
  }
  validate_absolute_path($home_dir)

  # ignore $uid and $gid, even if they are passed
  if $ignore_uid_gid {
    $_uid = undef
    $_gid = undef
  } else {
    $_uid = $uid
    $_gid = $gid ? {
      undef   => $uid,
      default => $gid,
    }
  }

  # Define the resources
  if $manage_group {
    group { $username:
      ensure => $ensure,
      gid    => $_gid,
      system => $system,
    }
  }
  user { $username:
    ensure         => $ensure,
    uid            => $_uid,
    gid            => $_gid,
    groups         => $groups,
    shell          => $shell,
    comment        => $comment,
    managehome     => $manage_home,
    home           => $home_dir,
    password       => $password,
    purge_ssh_keys => $purge_ssh_keys,
    system         => $system,
  }

  # ensure resource ordering and proper cleanup
  case $ensure {
    'absent': {
      if ($manage_home) and ($ssh_keys) {
        $ssh_key_defaults = {
          ensure => absent,
          user   => $username,
          'type' => 'ssh-rsa',
          before => User[$username],
        }
        create_resources('ssh_authorized_key',prefix($ssh_keys,"${name}-"),$ssh_key_defaults)
      }
      if $manage_group {
        User[$username] -> Group[$username]
      }
    }
    'present': {
      if $manage_group {
        Group[$username] -> User[$username]
      }
      if $ssh_keys {
        $ssh_key_defaults = {
          ensure => present,
          user   => $username,
          'type' => 'ssh-rsa'
        }
        create_resources('ssh_authorized_key',prefix($ssh_keys,"${name}-"),$ssh_key_defaults)
      }
      if $manage_home {
        $dotfiles_source = $manage_dotfiles ? {
          true    => "${::identity::dotfiles_source}/${username}",
          default => undef,
        }
        if $manage_group {
          $_group = $_gid
        } else {
          $_group = $username
        }
        file { $home_dir:
          ensure  => directory,
          source  => $dotfiles_source,
          recurse => $home_perms_recursive,
          owner   => $username,
          group   => $_group,
          mode    => $home_perms,
        }
      }
    }
    default: {
      fail('The $ensure parameter must be \'absent\' or \'present\'')
    }
  }

}
