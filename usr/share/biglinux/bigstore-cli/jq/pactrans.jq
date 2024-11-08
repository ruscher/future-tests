# Convert pactrans output in json
# Example of use:

# upgrade
# pactrans --sysupgrade --yolo --print-only | jq -Rn -f pactrans.jq

# install
# pactrans --install --yolo --print-only gimp | jq -Rn -f pactrans.jq

# remove
# pactrans --remove --yolo --print-only --cascade --recursive --unneeded gimp | jq -Rn -f pactrans.jq

# Tips for regex used in def:
#
# ^ and $ are anchors that match the start and end of a line, respectively, ensuring the whole line fits the pattern.
# (.*): captures any character sequence before a colon :, typically representing the package name.
# local \\((.*)\\) captures the version of the package installed locally.
#  The double backslashes \\ are used to escape the parentheses in the jq string, which means single
# backslashes are used in the actual regex to match literal parentheses.
# is newer than is a literal string that separates the local version from the repository version information.
# ([^ ]*) captures the repository's name, using [^ ]* to match any character except a space,
# ensuring it only captures the word immediately after "is newer than".
# \\((.*)\\) captures the repository version, similarly enclosed in escaped parentheses.

# def in this case is used to define value like a variable
def regex_newer_than: "^(.*): local \\((.*)\\) is newer than ([^ ]*) \\(([^)]*)\\)$";
def regex_replaced_packages: "^:: replacing package '([^']*)' with '([^']*)'";
def regex_provides_dependency: "^:: selecting package '([^']*)' as provider for dependency '([^']*)'";
def regex_conflict_remove: "^:: uninstalling package '([^']*)' due to conflict with '([^']*)'";
def regex_remove: "^removing local/([^ ]*) \\(([^ )]*)";
def regex_install: "^installing ([^/]*)/([^ ]*) \\(([^) ]*)\\)";
def regex_update: "^installing ([^/]*)/([^ ]*) \\(([^ ]*) -> ([^)]*)\\)";
def regex_download_size: "^Download Size: +(.[0-9.]+) ([A-Z])";
def regex_installed_size: "^Installed Size: +(.[0-9.]+) ([A-Z])";
def regex_size_delta: "^Size Delta: +(.[0-9.]+) ([A-Z])$";
def regex_error: "^error: +(.*)";
def regex_error_missing_dependency: "^error: missing dependency +(.*)";
def regex_lock_database: "unable to lock database";


inputs
| select(. != "")
| . as $line
| if test(regex_install) then
    ($line | match(regex_install)) | {
      "type": "install",
      "data": { "repo": .captures[0].string,
                "package": .captures[1].string,
                "version": .captures[2].string }
    }
  elif test(regex_update) then
    ($line | match(regex_update)) | {
      "type": (
        if .captures[2].string == .captures[3].string then
          "reinstall"
        else
          "update"
        end
      ),
      "data": {
        "repo": .captures[0].string,
        "package": .captures[1].string,
        "old_version": .captures[2].string,
        "new_version": .captures[3].string
      }
    }
  elif test(regex_remove) then
    ($line | match(regex_remove)) | {
      "type": "remove",
      "data": { "package": .captures[0].string,
                "version": .captures[1].string }
    }
  elif test(regex_newer_than) then # if the line matches the regex
      ($line | match(regex_newer_than)) | { # then capture the groups and create an object
        "type": "newer_local_version", # with a type field and a data field
        "data": { "package": .captures[0].string, # the data field contains the captured groups in regex is first part inner parentheses
                  "local_version": .captures[1].string, # is the second part inner parentheses
                  "repository": .captures[2].string, # is the third part inner parentheses
                  "repository_version": .captures[3].string } # is the fourth part inner parentheses
    }
  elif test(regex_replaced_packages) then
    ($line | match(regex_replaced_packages)) | {
      "type": "package_replacement",
      "data": { "old_package": .captures[0].string,
                "new_package": .captures[1].string }
    }
  elif test(regex_provides_dependency) then
    ($line | match(regex_provides_dependency)) | {
      "type": "provides_dependency",
      "data": { "package": .captures[0].string,
                "dependency": .captures[1].string }
    }
  elif test(regex_conflict_remove) then
    ($line | match(regex_conflict_remove)) | {
      "type": "conflict_remove",
      "data": { "package": .captures[0].string,
                "conflict_with": .captures[1].string }
    }
 elif test(regex_download_size) then
  ($line | match(regex_download_size)) | {
   "type": "download_size",
   "data": {
     "size": .captures[0].string,
     "unit": .captures[1].string,
     "size_in_bytes": ( # This is a subexpression that calculates the size in bytes, multiplying the size by the appropriate factor
       if .captures[1].string == "K" then .captures[0].string | tonumber * 1024
       elif .captures[1].string == "M" then .captures[0].string | tonumber * 1024 * 1024
       elif .captures[1].string == "G" then .captures[0].string | tonumber * 1024 * 1024 * 1024
       else .captures[0].string | tonumber
       end
     )
   }
  }
elif test(regex_lock_database) then
    ($line | match(regex_lock_database)) | {
      "type": "error",
      "data": { "type": "database",
                "msg": "unable to lock database" }
    }
  elif test(regex_installed_size) then
    ($line | match(regex_installed_size)) | {
      "type": "installed_size",
      "data": { "size": .captures[0].string,
                "unit": .captures[1].string }
    }
  elif test(regex_size_delta) then
    ($line | match(regex_size_delta)) | {
      "type": "size_delta",
      "data": { "size": .captures[0].string,
                "unit": .captures[1].string }
    }
  elif test(regex_error) then
    if test(regex_error_missing_dependency) then
      ($line | match(regex_error_missing_dependency)) | {
        "type": "error",
        "data": { "type": "missing_dependency",
          "msg": .captures[0].string }
      }
    else
      ($line | match(regex_error)) | {
        "type": "error",
        "data": { "type": "generic",
           "msg": .captures[0].string }
      }
    end
  else
    null
  end
| select(. != null)   # remove null values
