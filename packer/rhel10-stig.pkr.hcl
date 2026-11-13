packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "rhel10" {
  region          = "us-east-1"
  source_ami      = "ami-038a727c6c8b5450a"
  instance_type   = "t3.micro"
  ssh_username    = "ec2-user"
  ami_name        = "rhel10-stig-{{timestamp}}"
  ami_description = "RHEL 10 hardened to DISA STIG"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.rhel10"]

  provisioner "shell" {
    inline = [
      "sudo dnf install -y git ansible-core",
      "git clone https://github.com/ceaudette/govcloud-lab.git /tmp/govcloud-lab",
      "ansible-galaxy install -r /tmp/govcloud-lab/requirements.yml"
    ]
  }

  provisioner "shell" {
    inline = [
      "cd /tmp/govcloud-lab",
      "printf '[linux]\nlocalhost ansible_connection=local\n' > inventory-build.ini",
      "printf -- '---\n- name: STIG baseline\n  hosts: linux\n  become: true\n  roles:\n    - kernel_params\n    - pam_auth\n' > build.yml",
      "ansible-playbook -i inventory-build.ini build.yml"
    ]
  }
}
