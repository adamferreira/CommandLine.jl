function add_sudo_user {
    user=$1
    useradd -r -m -U -G sudo -d /home/${user} -s /bin/bash ${user}
    echo "${user} ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/${user}
}

add_sudo_user $1