$(document).ready ->

	build_table = (rows, cols) =>
		letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		table   = $ "<table class=\"table table-bordered\"></table>"
		for i in [0..rows]
			row = $ "<tr></tr>"
			for j in [0..cols]
				col = if i == 0 or j == 0 then $ "<th></th>" else $ "<td></td>"
				if i == 0 and j == 0 then col.addClass "border top"
				if i == 0 and j >  0 
					col.text letters[j-1]
					col.addClass "border top"
				if i > 0  and j == 0
					col.text i
					col.addClass "border left"
				if i > 0  and j >  0 then col.addClass "#{letters[j-1]}#{i} cell"
				row.append col
			table.append row

	$(".team1 .board").html build_table 5, 5
	$(".team2 .board").html build_table 5, 5

	end_editing = (event, target) ->
		target = target ? $(this)
		name = target.siblings ".name"
		name.text target.val()
		target.hide()
		name.show()

	$(".name-edit").focusout end_editing
	$(".name-edit").keyup (event) ->
		if event.keyCode == 13 then end_editing event, $(this)

	$(".name").click ->
		$(this).hide()
		edit = $(this).siblings ".name-edit"
		edit.val $(this).text()
		edit.show()
		edit.focus()

	socket = io.connect "http://localhost:3030"
	socket.emit "state"
	socket.on "id", ->
		socket.emit "ui"

	$("button.init").click ->
		$(this).addClass "hidden"
		$(".board").removeClass "spacer"
		$(".name").removeClass "hidden"
		$("button.test").removeClass "hidden"
		$("button.game").removeClass "hidden"

		$(".team1").addClass "game"
		$(".team2").addClass "game"

		$(".board td.cell").removeClass "off"
		$(".board td.cell").addClass "sea"
		$(".cell.ship").addClass "noshow"

	clear_board = ->
		$(".board td.cell").removeClass "off red white noshow ship"

	win_sound = [$("#team1_win")[0], $("#team2_win")[0]]
	for s in win_sound
		s.addEventListener "ended", ->
			stop()

	stop = ->
		$("button.stop").addClass "hidden"
		for s in win_sound
			s.pause()
			s.currentTime = 0

	$("button.test").click ->
		if $(this).hasClass "disabled" then return
		stop()

		$(".team1").removeClass "hidden"
		$(".team2").removeClass "hidden"
		$("button.game").removeClass "disabled"
		$(".team1 .done").addClass "hidden"
		$(".team2 .done").addClass "hidden"
		$(".team1 .name").removeClass "turn"
		$(".team2 .name").removeClass "turn"

		socket.emit "mode", "test"

		clear_board()

	$("button.game").click ->
		if $(this).hasClass "disabled" then return
		
		stop()
		clear_board()
		
		socket.emit "mode", "ship"

		$(this).addClass "disabled"
		$(".team1").removeClass "hidden"
		$(".team2").addClass    "hidden"
		$(".team1 .done").removeClass "hidden"
		$(".team2 .done").addClass    "hidden"
		$(".team1 .name").removeClass "turn"
		$(".team2 .name").removeClass "turn"

	$(".team1 .done button").click ->
		if $(this).hasClass "disabled" then return
		
		socket.emit "mode", "team"

		$(".team1").addClass    "hidden"
		$(".team2").removeClass "hidden"
		$(".team1 .done").addClass    "hidden"
		$(".team2 .done").removeClass "hidden"

	$(".team2 .done button").click ->
		if $(this).hasClass "disabled" then return
		
		$(".cell.ship").addClass "noshow"
		socket.emit "mode", "game"
		
		$("button.game").removeClass "disabled"
		$(".team1").removeClass    "hidden"
		$(".team2 .done").addClass "hidden"

	$("button.stop").click ->
		if $(this).hasClass "disabled" then return
		stop()

	update_cell = (id, state, ship) ->
		id = id.split ""
		if id.length != 3 then return
		cell = $ ".team#{id[0]} .#{id[1]}#{id[2]}"
		cell.removeClass "off"
		cell.removeClass "red"
		cell.removeClass "white"
		cell.removeClass "ship"
		if ship then cell.addClass "ship"
		cell.addClass state

	socket.on "state", (state) ->
		console.log "State:"
		console.log state
		update_cell id,s,state[1][id] for id,s of state[0]

	socket.on "update", (update) ->
		console.log "Update: #{update}"
		update_cell update...

	socket.on "turn", (team) ->
		$(".team1 .name").removeClass "turn"
		$(".team2 .name").removeClass "turn"
		$(".team#{team} .name").addClass "turn"

		console.log "Team #{team} turn"

	socket.on "winner", (team) ->
		console.log "Winner: #{team}"
		name = $(".team#{team} .name").text()
		$(".popup .modal-body").empty()
		$(".popup .modal-body").append $("<h1>Winner:<h1>")
		$(".popup .modal-body").append $("<h2>#{name}<h2>")
		$(".popup").modal()

		win_sound[team-1].play()

		$(".team1 .name").removeClass "turn"
		$(".team2 .name").removeClass "turn"
		$("button.stop").removeClass "hidden"
		$(".cell.ship" ).removeClass "noshow"

	window.socket
