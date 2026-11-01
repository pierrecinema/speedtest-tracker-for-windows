{
	admin off
	auto_https off
	persist_config off
}

:{{PORT}} {
	root * "{{ROOT}}/app/public"
	encode gzip
	php_fastcgi 127.0.0.1:9101 127.0.0.1:9102 127.0.0.1:9103 {
		lb_try_duration 5s
	}
	file_server
	log {
		output file "{{DATA}}/logs/access.log" {
			roll_size 10mb
			roll_keep 2
		}
	}
}
