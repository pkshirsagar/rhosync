# git-gui remote branch deleting support
# Copyright (C) 2007 Shawn Pearce

class remote_branch_delete {

field w
field head_m

field urltype   {url}
field remote    {}
field url       {}

field checktype  {head}
field check_head {}

field status    {}
field idle_id   {}
field full_list {}
field head_list {}
field active_ls {}
field head_cache
field full_cache
field cached

constructor dialog {} {
	global all_remotes M1B

	make_toplevel top w
	wm title $top "[appname] ([reponame]): Delete Remote Branch"
	if {$top ne {.}} {
		wm geometry $top "+[winfo rootx .]+[winfo rooty .]"
	}

	label $w.header -text {Delete Remote Branch} -font font_uibold
	pack $w.header -side top -fill x

	frame $w.buttons
	button $w.buttons.delete -text Delete \
		-default active \
		-command [cb _delete]
	pack $w.buttons.delete -side right
	button $w.buttons.cancel -text {Cancel} \
		-command [list destroy $w]
	pack $w.buttons.cancel -side right -padx 5
	pack $w.buttons -side bottom -fill x -pady 10 -padx 10

	labelframe $w.dest -text {From Repository}
	if {$all_remotes ne {}} {
		radiobutton $w.dest.remote_r \
			-text {Remote:} \
			-value remote \
			-variable @urltype
		eval tk_optionMenu $w.dest.remote_m @remote $all_remotes
		grid $w.dest.remote_r $w.dest.remote_m -sticky w
		if {[lsearch -sorted -exact $all_remotes origin] != -1} {
			set remote origin
		} else {
			set remote [lindex $all_remotes 0]
		}
		set urltype remote
		trace add variable @remote write [cb _write_remote]
	} else {
		set urltype url
	}
	radiobutton $w.dest.url_r \
		-text {Arbitrary URL:} \
		-value url \
		-variable @urltype
	entry $w.dest.url_t \
		-borderwidth 1 \
		-relief sunken \
		-width 50 \
		-textvariable @url \
		-validate key \
		-validatecommand {
			if {%d == 1 && [regexp {\s} %S]} {return 0}
			return 1
		}
	trace add variable @url write [cb _write_url]
	grid $w.dest.url_r $w.dest.url_t -sticky we -padx {0 5}
	grid columnconfigure $w.dest 1 -weight 1
	pack $w.dest -anchor nw -fill x -pady 5 -padx 5

	labelframe $w.heads -text {Branches}
	listbox $w.heads.l \
		-height 10 \
		-width 70 \
		-listvariable @head_list \
		-selectmode extended \
		-yscrollcommand [list $w.heads.sby set]
	scrollbar $w.heads.sby -command [list $w.heads.l yview]

	frame $w.heads.footer
	label $w.heads.footer.status \
		-textvariable @status \
		-anchor w \
		-justify left
	button $w.heads.footer.rescan \
		-text {Rescan} \
		-command [cb _rescan]
	pack $w.heads.footer.status -side left -fill x
	pack $w.heads.footer.rescan -side right

	pack $w.heads.footer -side bottom -fill x
	pack $w.heads.sby -side right -fill y
	pack $w.heads.l -side left -fill both -expand 1
	pack $w.heads -fill both -expand 1 -pady 5 -padx 5

	labelframe $w.validate -text {Delete Only If}
	radiobutton $w.validate.head_r \
		-text {Merged Into:} \
		-value head \
		-variable @checktype
	set head_m [tk_optionMenu $w.validate.head_m @check_head {}]
	trace add variable @head_list write [cb _write_head_list]
	trace add variable @check_head write [cb _write_check_head]
	grid $w.validate.head_r $w.validate.head_m -sticky w
	radiobutton $w.validate.always_r \
		-text {Always (Do not perform merge checks)} \
		-value always \
		-variable @checktype
	grid $w.validate.always_r -columnspan 2 -sticky w
	grid columnconfigure $w.validate 1 -weight 1
	pack $w.validate -anchor nw -fill x -pady 5 -padx 5

	trace add variable @urltype write [cb _write_urltype]
	_rescan $this

	bind $w <Key-F5>     [cb _rescan]
	bind $w <$M1B-Key-r> [cb _rescan]
	bind $w <$M1B-Key-R> [cb _rescan]
	bind $w <Key-Return> [cb _delete]
	bind $w <Key-Escape> [list destroy $w]
	return $w
}

method _delete {} {
	switch $urltype {
	remote {set uri $remote}
	url    {set uri $url}
	}

	set cache $urltype:$uri
	set crev {}
	if {$checktype eq {head}} {
		if {$check_head eq {}} {
			tk_messageBox \
				-icon error \
				-type ok \
				-title [wm title $w] \
				-parent $w \
				-message "A branch is required for 'Merged Into'."
			return
		}
		set crev $full_cache("$cache\nrefs/heads/$check_head")
	}

	set not_merged [list]
	set need_fetch 0
	set have_selection 0
	set push_cmd [list git push]
	lappend push_cmd -v
	lappend push_cmd $uri

	foreach i [$w.heads.l curselection] {
		set ref [lindex $full_list $i]
		if {$crev ne {}} {
			set obj $full_cache("$cache\n$ref")
			if {[catch {set m [git merge-base $obj $crev]}]} {
				set need_fetch 1
				set m {}
			}
			if {$obj ne $m} {
				lappend not_merged [lindex $head_list $i]
				continue
			}
		}

		lappend push_cmd :$ref
		set have_selection 1
	}

	if {$not_merged ne {}} {
		set msg "The following branches are not completely merged into $check_head:

 - [join $not_merged "\n - "]"

		if {$need_fetch} {
			append msg "

One or more of the merge tests failed because you have not fetched the necessary commits.  Try fetching from $uri first."
		}

		tk_messageBox \
			-icon info \
			-type ok \
			-title [wm title $w] \
			-parent $w \
			-message $msg
		if {!$have_selection} return
	}

	if {!$have_selection} {
		tk_messageBox \
			-icon error \
			-type ok \
			-title [wm title $w] \
			-parent $w \
			-message "Please select one or more branches to delete."
		return
	}

	if {[tk_messageBox \
		-icon warning \
		-type yesno \
		-title [wm title $w] \
		-parent $w \
		-message {Recovering deleted branches is difficult.

Delete the selected branches?}] ne yes} {
		return
	}

	destroy $w

	set cons [console::new \
		"push $uri" \
		"Deleting branches from $uri"]
	console::exec $cons $push_cmd
}

method _rescan {{force 1}} {
	switch $urltype {
	remote {set uri $remote}
	url    {set uri $url}
	}

	if {$force} {
		unset -nocomplain cached($urltype:$uri)
	}

	if {$idle_id ne {}} {
		after cancel $idle_id
		set idle_id {}
	}

	_load $this $urltype:$uri $uri
}

method _write_remote     {args} { set urltype remote }
method _write_url        {args} { set urltype url    }
method _write_check_head {args} { set checktype head }

method _write_head_list {args} {
	$head_m delete 0 end
	foreach abr $head_list {
		$head_m insert end radiobutton \
			-label $abr \
			-value $abr \
			-variable @check_head
	}
	if {[lsearch -exact -sorted $head_list $check_head] < 0} {
		set check_head {}
	}
}

method _write_urltype {args} {
	if {$urltype eq {url}} {
		if {$idle_id ne {}} {
			after cancel $idle_id
		}
		_load $this none: {}
		set idle_id [after 1000 [cb _rescan 0]]
	} else {
		_rescan $this 0
	}
}

method _load {cache uri} {
	if {$active_ls ne {}} {
		catch {close $active_ls}
	}

	if {$uri eq {}} {
		$w.heads.l conf -state disabled
		set head_list [list]
		set full_list [list]
		set status {No repository selected.}
		return
	}

	if {[catch {set x $cached($cache)}]} {
		set status "Scanning $uri..."
		$w.heads.l conf -state disabled
		set head_list [list]
		set full_list [list]
		set head_cache($cache) [list]
		set full_cache($cache) [list]
		set active_ls [git_read ls-remote $uri]
		fconfigure $active_ls \
			-blocking 0 \
			-translation lf \
			-encoding utf-8
		fileevent $active_ls readable [cb _read $cache $active_ls]
	} else {
		set status {}
		set full_list $full_cache($cache)
		set head_list $head_cache($cache)
		$w.heads.l conf -state normal
	}
}

method _read {cache fd} {
	if {$fd ne $active_ls} {
		catch {close $fd}
		return
	}

	while {[gets $fd line] >= 0} {
		if {[string match {*^{}} $line]} continue
		if {[regexp {^([0-9a-f]{40})	(.*)$} $line _junk obj ref]} {
			if {[regsub ^refs/heads/ $ref {} abr]} {
				lappend head_list $abr
				lappend head_cache($cache) $abr
				lappend full_list $ref
				lappend full_cache($cache) $ref
				set full_cache("$cache\n$ref") $obj
			}
		}
	}

	if {[eof $fd]} {
		if {[catch {close $fd} err]} {
			set status $err
			set head_list [list]
			set full_list [list]
		} else {
			set status {}
			set cached($cache) 1
			$w.heads.l conf -state normal
		}
	}
} ifdeleted {
	catch {close $fd}
}

}
