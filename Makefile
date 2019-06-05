SHELL = /bin/bash

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
-include munkiadmin.env
export

help:
	@echo -e "\n> \033[4mHelp\033[0m\n"
	@echo -e "  make configure,\033[35m\xe2\x86\x92\033[0m,Configure munkimagic-MunkiAdmin\n\
	  make setup,\033[35m\xe2\x86\x92\033[0m,Clone Munki git repository into \033[35m\xe2\x86\xb4\033[0m\n\
	  ,\033[35m\033[0m,$(MAKEFILE_DIR)\033[4m$${munki_repo-<repo_name>}\033[0m/\n\
	  ,,\n\
	  make status,\033[35m\xe2\x86\x92\033[0m,Show the working tree status of the munki repository\n\
	  make commit,\033[35m\xe2\x86\x92\033[0m,Commit changes made to the munki repository\n\
	  make update,\033[35m\xe2\x86\x92\033[0m,Push changes and update Munki bucket\n\
	  ,,\n\
	  make reset,\033[35m\xe2\x86\x92\033[0m,Reset configuration" | /usr/bin/column -s "," -t
	@echo ""

requirements:
	@[[ -z $${aws_profile} || -z $${name} || -z $${email} || -z $${aws_region} || -z $${munki_s3_bucket} || -z $${munki_repo} ]] \
		&& echo -e "\n\033[31m!\033[0m Not all environment variables set. Please run \`make configure\`.\n" \
		&& exit 1 \
		|| :
	@if ! type aws &> /dev/null;then \
		echo -e "\n\033[31m!\033[0m Please install aws-cli."; \
		echo -e "\n\033[35m\xe2\x86\x92\033[0m https://docs.aws.amazon.com/cli/latest/userguide/cli-install-macos.html\n"; \
		exit 1; \
	fi
	@if ! type git &> /dev/null;then \
		echo -e "\n\033[31m!\033[0m Please install git."; \
		exit 1; \
	fi
	@-if [[ $(MAKECMDGOALS) == "push" || $(MAKECMDGOALS) == "pull" || $(MAKECMDGOALS) == "commit" ]];then \
		[[ -z $${repo_cloned} ]] \
			&& echo -e "\n\033[31mx\033[0m Please run \`make setup\` first.\n" \
			&& exit 1 \
			|| :; \
	fi;

configure:
	@echo -e "\n\033[35m\xe2\x86\x92\033[0m \033[1;4mEnvironment\033[0m\n"
	@if [[ -z $${aws_profile} ]];then \
		while ! /usr/bin/grep -qw "^\[$${aws_profile}\]$$" ~/.aws/credentials;do \
			[ $${profile_check} ] && echo -e "\033[31mx\033[0m Profile '$${aws_profile}' does not exist."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter the name of the AWS profile to use: " aws_profile; \
			/usr/bin/tput cuu 1 && /usr/bin/tput el; \
			profile_check=1; \
		done; \
		echo "aws_profile=$${aws_profile}" >> munkiadmin.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m AWS profile set to '$${aws_profile}'"; \
	if [[ -z $${aws_region} ]];then \
		available_regions=( $$(aws ec2 describe-regions --query "Regions[].{Name:RegionName}" --output text 2>/dev/null) ); \
		if [[ -z $${available_regions[@]} ]];then \
			echo -e "\033[31mx\033[0m Setting region\033[31m [ERROR]\033[0m"; \
			echo -e "\n  Please make sure you are online and you selected the correct profile.\n"; \
			exit 1; \
		fi; \
		while ! printf '%s\n' $${available_regions[@]} | /usr/bin/grep -qw "^$${aws_region}$$";do \
			[[ $${region_check} ]] && echo -e "\033[31mx\033[0m Region '$${aws_region}' does not exist."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter an AWS region [eu-west-1]: " aws_region; \
			/usr/bin/tput cuu 1 && /usr/bin/tput el; \
			aws_region=$${aws_region:-eu-west-1}; \
			aws_region=$$(echo $${aws_region} | /usr/bin/tr "[:upper:]" "[:lower:]"); \
			region_check=1; \
		done; \
		echo "aws_region=$${aws_region}" >> munkiadmin.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Region set to '$${aws_region}'"; \
	if [[ -z $${name} ]];then \
		name=$$(echo $${name} | /usr/bin/tr -cd '[a-zA-Z ]'); \
		echo -en "\033[34m\xe2\x86\x92\033[0m"; \
		read -p " Enter your Name: " name; \
		/usr/bin/tput cuu 1 && /usr/bin/tput el; \
		echo "name='$${name}'" >> munkiadmin.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Name set to '$${name}'"; \
	if [[ -z $${email} ]];then \
		echo -en "\033[34m\xe2\x86\x92\033[0m"; \
		read -p " Enter your E-Mail address: " email; \
		/usr/bin/tput cuu 1 && /usr/bin/tput el; \
		echo "email=$${email}" >> munkiadmin.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m E-Mail set to '$${email}'"; \
	if [[ -z $${ssh_key_id} ]];then \
		echo -en "\033[34m\xe2\x86\x92\033[0m"; \
		read -p " SSH key ID: " ssh_key_id; \
		/usr/bin/tput cuu 1 && /usr/bin/tput el; \
		echo "ssh_key_id=$${ssh_key_id}" >> munkiadmin.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m SSH key ID set to '$${ssh_key_id}'"; \
	if [[ -z $${identity_file} ]];then \
		while ! [[ -f "$${identity_file}" ]];do \
			[[ $${check_file} ]] && echo -e "\033[31mx\033[0m File '$${identity_file}' does not exist."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -e -p " Enter the location of your private ssh key [~/.ssh/munkimagic.id_rsa]: " identity_file; \
			eval identity_file=$${identity_file:-~/.ssh/munkimagic.id_rsa}; \
			/usr/bin/tput cuu 1 && /usr/bin/tput el; \
			check_file=1; \
		done; \
		echo "identity_file=$${identity_file}" >> munkiadmin.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Identity file set to '$${identity_file}'"; \
	if [[ -z $${munki_stack} ]];then \
		while [[ "$$(aws --profile $${aws_profile} --region $${aws_region} cloudformation describe-stacks --stack-name $${munki_stack} --query 'Stacks[].StackName' --output text 2>/dev/null)" != "$${munki_stack}" ]] || [[ ! $${munki_stack} =~ ^[A-Za-z-]+$$ ]];do \
			[[ $${munki_stack_check} ]] && echo -e "\033[31mx\033[0m Stack name '$${munki_stack}' is incorrect."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter stack name: " munki_stack; \
			/usr/bin/tput cuu 1 && /usr/bin/tput el; \
			munki_stack_check=1; \
		done; \
		echo "munki_stack=$${munki_stack}" >> munkiadmin.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Stack name set to '$${munki_stack}'"; \
	if [[ -z $${munki_repo} ]];then \
		while /usr/bin/true;do \
			[[ $$(echo $${result} | /usr/bin/grep 'AccessDeniedException') ]] && echo -e "\033[31mx\033[0m Repository name '$${munki_repo}' is incorrect."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter name for CodeCommit repository [$${munki_stack}]: " munki_repo; \
			/usr/bin/tput cuu 1 && /usr/bin/tput el; \
			munki_repo=$${munki_repo:-$${munki_stack}}; \
			munki_repo=$$(echo $${munki_repo} | /usr/bin/tr "[:upper:]" "[:lower:]"); \
			result=$$(aws --profile $${aws_profile} --region $${aws_region} codecommit get-repository --repository-name $${munki_repo} --query 'repositoryMetadata.repositoryName' --output text 2>&1); \
			repo_check=1; \
			[[ $${result} == $${munki_repo} ]] && break; \
		done; \
		echo "munki_repo=$${munki_repo}" >> munkiadmin.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Munki repository set to '$${munki_repo}'"; \
	if [[ -z $${munki_s3_bucket} ]];then \
		while true;do \
			munki_s3_bucket=$$(echo $${munki_s3_bucket} | /usr/bin/tr "[:upper:]" "[:lower:]"); \
			munki_s3_bucket=$${munki_s3_bucket}; \
			[[ $$(echo $${result} | /usr/bin/grep 'NoSuchBucket') ]] && echo -e "\033[31mx\033[0m Bucket '$${munki_s3_bucket}' does not exist."; \
			[[ $$(echo $${result} | /usr/bin/grep 'AccessDenied') ]] && echo -e "\033[31mx\033[0m Access to bucket '$${munki_s3_bucket}' denied."; \
			echo -en "\033[34m\xe2\x86\x92\033[0m"; \
			read -p " Enter name for munki repository bucket [$${munki_stack}]: " munki_s3_bucket; \
			munki_s3_bucket=$${munki_s3_bucket:-$${munki_stack}}; \
			munki_s3_bucket=$$(echo $${munki_s3_bucket} | /usr/bin/tr "[:upper:]" "[:lower:]"); \
			/usr/bin/tput cuu 1 && /usr/bin/tput el; \
			result=$$(aws --profile $${aws_profile} s3 ls "s3://$${munki_s3_bucket}/pkgs" 2>&1); \
			[[ $${?} == 0 || $${?} == 1 ]] && break; \
		done; \
		echo "munki_s3_bucket=$${munki_s3_bucket}" >> munkiadmin.env; \
	fi; \
	echo -e "\033[32m\xE2\x9C\x94\033[0m Munki bucket name set to '$${munki_s3_bucket}'"; \
	echo ""

setup: requirements
	@echo -e "\n\033[35m>\033[0m \033[1;4mSet up repository\033[0m"; \
	/bin/mkdir -p $${munki_repo}; \
	cd $(MAKEFILE_DIR)/$${munki_repo}; \
	if ! /usr/bin/grep -qw "Host $${munki_repo}" ~/.ssh/config;then \
		! [[ -d ~/.ssh ]] && /bin/mkdir ~/.ssh; \
		echo "Host $${munki_repo}" >> ~/.ssh/config; \
		echo "  Hostname git-codecommit.$${aws_region}.amazonaws.com" >> ~/.ssh/config; \
		echo "  User $${ssh_key_id}" >> ~/.ssh/config; \
		echo "  IdentityFile $${identity_file}" >> ~/.ssh/config; \
	fi; \
	if ! [[ -f $(MAKEFILE_DIR)$${munki_repo}/.git/config ]];then \
		git init >/dev/null 2>&1; \
		git remote add origin ssh://$${munki_repo}/v1/repos/$${munki_repo} >/dev/null 2>&1; \
		git config --local user.email "$${email}"; \
		git config --local user.name "$${name}"; \
	fi; \
	! [[ -f $(MAKEFILE_DIR)$${munki_repo}/.gitignore ]] \
		&& echo -e ".gitignore\n.DS_Store\n/pkgs/\n/catalogs/" > $(MAKEFILE_DIR)$${munki_repo}/.gitignore; \
	if [[ -z $${repo_cloned} ]];then \
		cd $(MAKEFILE_DIR)$${munki_repo}; \
		echo -e "\n\033[34m\xe2\x86\x92\033[0m Setting up repository ..."; \
		result=$$(git pull origin master 2>&1); \
		[[ $$(echo $${result} | /usr/bin/grep "From ssh://$${munki_repo}/v1/repos/$${munki_repo}") || $$(echo $${result} | /usr/bin/grep "fatal: Couldn't find remote ref master") ]] \
			&& echo "repo_cloned=1" >> ../munkiadmin.env \
			&& /usr/bin/tput cuu 1 && /usr/bin/tput el \
			&& echo -e "\033[32m\xE2\x9C\x94\033[0m Successfully set up repository.\n" \
			|| echo -e "\n\033[31mx\033[0m Setup error.\n"; \
	else \
		echo -e "\n\033[31m!\033[0m Repository already set up.\n"; \
	fi

pull: requirements
	@echo -e "\n\033[35m>\033[0m \033[1;4mPull changes\033[0m\n"; \
	cd $(MAKEFILE_DIR)$${munki_repo}; \
	result=$$(git pull origin master 2>&1); \
	if echo $${result} | /usr/bin/grep -q 'Already up to date';then \
		echo -e "\033[32m\xE2\x9C\x94\033[0m Local repository already up to date."; \
	elif echo $${result} | /usr/bin/grep -q 'fatal: Could not read from remote repository';then \
		echo -e "\033[31mx\033[0m fatal: Could not read from remote repository. Please make sure you have the correct access rights and the repository exists."; \
		exit 1; \
	else \
		echo -e "\033[32m\xE2\x9C\x94\033[0m New changes pulled."; \
	fi

commit:
	@echo -e "\n\033[35m>\033[0m \033[1;4mCommit changes\033[0m\n"; \
	cd $(MAKEFILE_DIR)$${munki_repo}; \
	result=$$(git status 2>&1); \
	if [[ $$(echo $${result} | /usr/bin/grep 'nothing to commit') ]];then \
		echo -e "\033[31m!\033[0m Nothing to commit.\n"; \
		exit 1; \
	else \
		echo -en "\033[34m\xe2\x86\x92\033[0m"; \
		read -e -p " Describe the changes you have made: " commit_message; \
		/usr/bin/tput cuu 1 && /usr/bin/tput el; \
		commit_message=$$(echo $${commit_message} | /usr/bin/tr -cd '[a-zA-Z0-9.,;\-_ ]'); \
		git add .; \
		result=$$(git commit -m "$${commit_message}" 2>&1); \
		if [[ $${?} == 0 ]];then \
			commit=$$(echo $${result} | /usr/bin/awk -F'[\\[|\\] ]' '{print $$3}'); \
			echo -e "\033[32m\xE2\x9C\x94\033[0m Changes have been commited ($${commit})."; \
		else \
			echo -e "\n\033[31mx\033[0m Something went wrong. \033[31m[ERROR]\033[0m"; \
			exit 1; \
		fi; \
	fi

push: requirements pull
	@echo -e "\n\033[35m>\033[0m \033[1;4mPush changes\033[0m\n"; \
	cd $(MAKEFILE_DIR)/$${munki_repo}; \
	result=$$(git push origin master 2>&1); \
	if [[ $$(echo $${result} | /usr/bin/grep 'Everything up-to-date') ]];then \
		echo -e "\033[33m!\033[0m Repository already up-to-date.\n"; \
		exit 1; \
	elif [[ $$(echo $${result} | /usr/bin/grep "To ssh://$${munki_repo}/v1/repos/$${munki_repo}") ]];then \
		echo -e "\033[32m\xE2\x9C\x94\033[0m Changes pushed to repository."; \
	fi

sync-packages: requirements
	@echo -e "\n\033[35m>\033[0m \033[1;4mSync Packages to s3://$${munki_s3_bucket}/pkgs\033[0m\n"; \
	exec 5>&1; \
	if ! [[ -d $${munki_repo} ]];then \
		echo -e "\033[31mx\033[0m Could not find repository locally. Did you run \`make setup\`? \033[31m[ERROR]\033[0m"; \
	elif [[ -d $${munki_repo}/pkgs ]];then \
		result=$$(aws --profile $${aws_profile} --region $${aws_region} s3 sync ./$${munki_repo}/pkgs s3://$${munki_s3_bucket}/pkgs --exclude *.DS_Store* 5>&2|/usr/bin/tee /dev/fd/5); \
		if [[ $$(echo $${result} | /usr/bin/grep "upload:") ]] && ! [[ $$(echo $${result} | /usr/bin/grep "upload failed:") ]];then \
			echo -e "\n\033[32m\xE2\x9C\x94\033[0m All packages synced."; \
		elif [[ $$(echo $${result} | /usr/bin/grep "upload failed:") ]];then \
			echo -e "\n\033[31m!\033[0m At least one upload failed."; \
			exit 1; \
		else \
			echo -e "\033[32m\xE2\x9C\x94\033[0m Packages already up-to-date."; \
		fi; \
	else \
		echo -e "\033[31m!\033[0m No local packages found."; \
	fi

update: sync-packages push
	@echo -e "\n\033[35m>\033[0m \033[1;4mPipeline status\033[0m\n"; \
	currentExecutionId=$$(aws --profile $${aws_profile} --region $${aws_region} codepipeline get-pipeline-state --name $${munki_stack}-CodePipeline --query 'stageStates[?stageName==`Build`].latestExecution[].pipelineExecutionId' --output text); \
	check=0; \
	echo -e "\033[34m\xe2\x86\x92\033[0m Waiting for pipeline ..."; \
	SECONDS=0; \
	while true;do \
		status=$$(aws --profile $${aws_profile} --region $${aws_region} codepipeline get-pipeline-state --name $${munki_stack}-CodePipeline --query 'stageStates[?stageName==`Build`].latestExecution[].pipelineExecutionId' --output text); \
		/bin/sleep 1; \
		if [[ $${status} == $${currentExecutionId} ]];then \
			/usr/bin/tput cuu 1 && /usr/bin/tput el; \
			echo -e "\033[34m\xe2\x86\x92\033[0m Waiting for pipeline ... [$${SECONDS}s]"; \
		else \
		buildStatus=$$(aws --profile $${aws_profile} --region $${aws_region} codepipeline get-pipeline-state --name $${munki_stack}-CodePipeline --query 'stageStates[?stageName==`Build`].latestExecution[].status' --output text); \
			if [[ $${buildStatus} != "Succeeded" ]];then \
				/usr/bin/tput cuu 1 && /usr/bin/tput el; \
				echo -e "\033[34m\xe2\x86\x92\033[0m Syncing manifests to S3 and making catalogs... [$${SECONDS}s]"; \
			else \
				/usr/bin/tput cuu 1 && /usr/bin/tput el; \
				echo -e "\033[32m\xE2\x9C\x94\033[0m Munki bucket is now up-to-date."; \
				break; \
			fi; \
		fi; \
	done; \
	echo ""

status: requirements
	@echo -e "\n\033[35m>\033[0m \033[1;4mGit status\033[0m\n"; \
	cd $(MAKEFILE_DIR)/$${munki_repo}; \
	git status

reset:
	@echo -e "\n\033[35m\xe2\x86\x92\033[0m \033[1;4mReset\033[0m"
	@[[ -f munkiadmin.env ]] \
		&& /bin/rm munkiadmin.env \
		&& echo -e "\n\033[32m\xE2\x9C\x94\033[0m Munki environment reset.\n" \
		|| echo -e "\n\033[31m!\033[0m Nothing to reset.\n"
	@[[ $${munki_repo} ]] \
		&& grep -qw "$${munki_repo}" ~/.ssh/config \
		&& echo -e "  Please manually remove the SSH Host configuration '$${munki_repo}' from  ~/.ssh/config\n" \
		|| :;
