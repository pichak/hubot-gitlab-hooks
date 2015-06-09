# Description:
#   Post gitlab related events using gitlab hooks to slack
#
# Dependencies:
#   "url" : ""
#   "querystring" : ""
#
# Configuration:
#   GITLAB_CHANNEL
#   GITLAB_DEBUG
#   GITLAB_BRANCHES
#   GITLAB_SHOW_COMMITS_LISTG
#   GITLAB_SHOW_MERGE_DESCRIPTION
#   GITLAB_BOTNAME
#   GITLAB_ICON
#
#   Put http://<HUBOT_URL>:<PORT>/gitlab/system as your system hook
#   Put http://<HUBOT_URL>:<PORT>/gitlab/web as your web hook (per repository)
#   You can also append "?targets=%23room1,%23room2" to the URL to control the
#   message destination.  Using the "target" parameter to override the 
#   GITLAB_CHANNEL configuration value.
#   You can also append "?branches=master,deve" to the URL to control the
#   message destination.  Using the "target" parameter to override the 
#   GITLAB_BRANCHES configuration value.
#
# Commands:
#   None
#
# URLS:
#   /gitlab/system
#   /gitlab/web
#
# Author:
#   omribahumi, spruce, milani
#

url = require 'url'
querystring = require 'querystring'

module.exports = (robot) ->
  gitlabChannel = process.env.GITLAB_CHANNEL or "#gitlab"
  showCommitsList = process.env.GITLAB_SHOW_COMMITS_LIST or "1"
  showMergeDesc = process.env.GITLAB_SHOW_MERGE_DESCRIPTION or "1"
  debug = process.env.GITLAB_DEBUG?
  branches = ['all']
  botname = process.env.GITLAB_BOTNAME or "Gitlab"
  boticon = process.env.GITLAB_ICON or "https://about.gitlab.com/ico/favicon.ico"
  if process.env.GITLAB_BRANCHES?
    branches = process.env.GITLAB_BRANCHES.split ','

  trim_commit_id = (id) ->
    id.replace(/([0-9a-f]{9})[0-9a-f]+$/, '$1')

  trim_commit_url = (url) ->
    url.replace(/(\/[0-9a-f]{9})[0-9a-f]+$/, '$1')

  handler = (type, req, res) ->
    query = querystring.parse(url.parse(req.url).query)
    hook = req.body

    #if debug
    console.log('query', query)
    console.log('hook', hook)

    user = {}
    user.room = if query.targets then query.targets else gitlabChannel
    user.type = query.type if query.type
    if query.branches
      branches = query.branches.split ','

    switch type
      when "system"
        switch hook.event_name
          when "project_create"
            robot.send user, "Yay! New gitlab project #{bold(hook.name)} created by #{bold(hook.owner_name)} (#{bold(hook.owner_email)})"
          when "project_destroy"
            robot.send user, "Oh no! #{bold(hook.owner_name)} (#{bold(hook.owner_email)}) deleted the #{bold(hook.name)} project"
          when "user_add_to_team"
            robot.send user, "#{bold(hook.project_access)} access granted to #{bold(hook.user_name)} (#{bold(hook.user_email)}) on #{bold(hook.project_name)} project"
          when "user_remove_from_team"
            robot.send user, "#{bold(hook.project_access)} access revoked from #{bold(hook.user_name)} (#{bold(hook.user_email)}) on #{bold(hook.project_name)} project"
          when "user_create"
            robot.send user, "Please welcome #{bold(hook.name)} (#{bold(hook.email)}) to Gitlab!"
          when "user_destroy"
            robot.send user, "We will be missing #{bold(hook.name)} (#{bold(hook.email)}) on Gitlab"
      when "web"
        message = ""
        # is it code being pushed?
        if hook.ref
          # should look for a tag push where the ref starts with refs/tags
          if /^refs\/tags/.test hook.ref
            # tag = hook.ref.split("/")[2..].join("/")
            # # this is actually a tag being pushed
            # if /^0+$/.test hook.before
            #   message = "#{bold(hook.user_name)} pushed a new tag (#{bold(tag)}) to #{bold(hook.repository.name)} (#{underline(hook.repository.homepage)})"
            # else if /^0+$/.test hook.after
            #   message = "#{bold(hook.user_name)} removed a tag (#{bold(tag)}) from #{bold(hook.repository.name)} (#{underline(hook.repository.homepage)})"
            # else
            #   message = "#{bold(hook.user_name)} pushed #{bold(hook.total_commits_count)} commits to tag (#{bold(tag)}) in #{bold(hook.repository.name)} (#{underline(hook.repository.homepage)})"
          else
            branch = hook.ref.split("/")[2..].join("/")
            # if the ref before the commit is 00000, this is a new branch
            if branch in branches or 'all' in branches
              if /^0+$/.test(hook.before)

                message = ''
                for commit in hook.commits
                  message += "<#{commit.url}|#{trim_commit_id(commit.id)}>: #{commit.message}\n"

                robot.emit 'slack-attachment', {
                  channel: user.room,
                  attachments: [{color:"#4183C4",text:message}],
                  username: botname,
                  icon_url: boticon,
                  text: "[#{hook.repository.name}] New branch \"<#{hook.repository.homepage}|#{branch}>\" pushed by #{hook.user_name}"
                }
              else if /^0+$/.test(hook.after)
                robot.emit 'slack-attachment', {
                  channel: user.room,
                  attachments: [{color:"#4183C4",text: "[#{hook.repository.name}] The branch \"#{branch}\" deleted by #{hook.user_name}"}],
                  username: botname,
                  icon_url: boticon,
                  text: ""
                }
              else

                message = ''
                for commit in hook.commits
                  message += "<#{commit.url}|#{trim_commit_id(commit.id)}>: #{commit.message}\n"

                robot.emit 'slack-attachment', {
                  channel: user.room,
                  attachments: [{color:"#4183C4",text:message}],
                  username: botname,
                  icon_url: boticon,
                  text: "[#{hook.repository.name}:#{branch}] #{hook.total_commits_count} new commits by #{hook.user_name}:"
                }

        # not code? must be a something good!
        else
          repo = hook.object_attributes.url.replace(/.*\/([^\/]+)\/(merge_requests|issues).*$/,"$1")
          repo_url = hook.object_attributes.url.replace(/\/(merge_requests|issues).*$/,"")
          switch hook.object_kind
            when "issue"
              switch hook.object_attributes.action
                when "update"
                  if hook.object_attributes.state == 'closed'
                    robot.emit 'slack-attachment', {
                      channel: user.room,
                      attachments: [{color:"#E3E4E6",text:"[<#{repo_url}|#{repo}>] Issue closed: <#{hook.object_attributes.url}|\##{hook.object_attributes.id} #{hook.object_attributes.title}> by #{hook.user.username}"}],
                      username: botname,
                      icon_url: boticon,
                      text: ""
                    }
                  else if hook.object_attributes.state == 'reopened'
                    robot.emit 'slack-attachment', {
                      channel: user.room,
                      attachments: [{color:"#FAD5A1",text:"[<#{repo_url}|#{repo}>] Issue reopened: <#{hook.object_attributes.url}|\##{hook.object_attributes.id} #{hook.object_attributes.title}> by #{hook.user.username}"}],
                      username: botname,
                      icon_url: boticon,
                      text: ""
                    }
                when "open"
                  message = "\##{hook.object_attributes.id} #{hook.object_attributes.title}"

                  robot.emit 'slack-attachment', {
                    channel: user.room,
                    attachments: [{color:"#F29513", title:message, title_link:"#{hook.object_attributes.url}"}],
                    username: botname,
                    icon_url: boticon,
                    text: "[<#{repo_url}|#{repo}>] Issue created by #{hook.user.username}"
                  }
            when "merge_request"
              if hook.object_attributes.state == "opened"
                merge_request_title = "<#{hook.object_attributes.url}|\##{hook.object_attributes.iid} #{hook.object_attributes.title}>"

                robot.emit 'slack-attachment', {
                  channel: user.room,
                  attachments: [{color:"#6CC644", title: merge_request_title, title_link: "#{hook.object_attributes.url}"}],
                  username: botname,
                  icon_url: boticon,
                  text: "[<#{repo_url}|#{repo}>] Pull request submitted by #{hook.user.username}"
                }
              else if hook.object_attributes.state == "merged"
                merge_request_title = "\##{hook.object_attributes.iid} #{hook.object_attributes.title}"

                robot.emit 'slack-attachment', {
                  channel: user.room,
                  attachments: [{color:"#E3E4E6", title: "[<#{repo_url}|#{repo}>] Pull request closed: <#{hook.object_attributes.url}|#{merge_request_title}> by #{hook.user.username}"}],
                  username: botname,
                  icon_url: boticon,
                  text: ""
                }

  robot.router.post "/gitlab/system", (req, res) ->
    handler "system", req, res
    res.end "OK"

  robot.router.post "/gitlab/web", (req, res) ->
    handler "web", req, res
    res.end "OK"
