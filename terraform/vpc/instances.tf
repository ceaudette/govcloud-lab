resource "aws_instance" "bastion" {
  ami                    = "ami-04398678fbf4b9275"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  key_name               = "govcloud-lab"
  vpc_security_group_ids = [aws_security_group.bastion.id]

  tags = {
    Name = "govcloud-lab-bastion"
  }
}

resource "aws_instance" "private" {
  ami                    = "ami-04398678fbf4b9275"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_a.id
  key_name               = "govcloud-lab"
  vpc_security_group_ids = [aws_security_group.private.id]

  tags = {
    Name = "govcloud-lab-private"
  }
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "private_instance_ip" {
  value = aws_instance.private.private_ip
}
