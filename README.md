# Install 

As root:

    podman pull ghcr.io/go-shiori/shiori

	podman run -d --rm --name shiori -p 8080:8080 -v /srv/shiori:/shiori ghcr.io/go-shiori/shiori
	podman generate systemd --new --name shiori > /etc/systemd/system/shiori.service
	podman container rm -f shiori
	systemctl daemon-reload
	systemctl enable shiori
	systemctl start shiori
	
# Upgrade (not tested)

As root:

    podman pull ghcr.io/go-shiori/shiori
    podman stop shiori # Stops the currently running container and loads a new one.
	
## Is it running?

Check status with:

	systemctl status shiori
	
Logs: 

    journalctl -u shiori # The systemd logs
    podman logs shiori   # The appliaction logs

	


