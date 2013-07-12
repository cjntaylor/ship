express = require "express"
play    = require "play"
gpio    = require "gpio"
fs      = require "fs"

class Player
	constructor: (id, host = "localhost", port = 3030) ->
		# Save and output the id information for the player
		@id = id
		console.log "Player ID: #{@id}"

		@r_led_ready  = false
		@w_led_ready  = false

		fs.exists "/sys/class/gpio", (exists) =>
			if exists
				@r_led  = gpio.export 23, {direction: "out", ready: =>
					@r_led_ready = true
				}
				@w_led  = gpio.export 24, {direction: "out", ready: =>
					@w_led_ready = true
				}
				@button = gpio.export 25, {direction: "in"}

		# Connect to the websocket server
		@socket = require("socket.io-client").connect "http://#{host}:#{port}"

		# Respond to requests for identity with the id object
		@socket.on "id", =>
			@socket.emit "id", @id

		# Display server connection status
		@socket.on "connected", =>
			console.log "Connected to server"

		@socket.on "takeoff", =>
			play.sound "./static/sound/takeoff.wav"

		@socket.on "doppler", =>
			play.sound "./static/sound/doppler.wav"

		@socket.on "hit", =>
			play.sound "./static/sound/hit.wav", =>
				console.log "HIT!"

		@socket.on "miss", =>
			play.sound "./static/sound/miss.wav", =>
				console.log "MISS!"


		# Invoke the off method (Turn LEDs off)
		@socket.on "off", =>
			@off()

		# Invoke the red method (Turn red LED on)
		@socket.on "red", =>
			@red()

		# Invoke the white method (Turn white LED on)
		@socket.on "white", =>
			@white()

		# Enable spacebar to serve as an alternate fire key
		require("keypress")(process.stdin)
		process.stdin.on "keypress", (ch, key) =>
			if key and key.ctrl and key.name is "c" then process.exit()
			else if key and key.name is "space"
				console.log "DEBUG: Fire"
				@fire()
		process.stdin.setRawMode true
		process.stdin.resume()

	off: =>

	red: =>

	white: =>

	fire: =>
		@socket.emit "fire", @id

class Ship
	constructor: (port = 3030) ->
		@socket = {}
		@state  = {}
		@ships  = {}
		@cols   = 5

		@fire = @test_mode

		# Create an express application to host the UI
		@app = express()
		@app.use "/static", express.static("static")
		@app.get "/", (req, res) ->
			res.sendfile "#{__dirname}/index.html"
		@app.get "/ship_ui.js", (req, res) ->
			res.sendfile "#{__dirname}/ship_ui.js"
		
		# Create a web server to host the app, and bind a websocket server to it
		@http = require("http").createServer @app
		@io   = require("socket.io").listen  @http

		@io.sockets.on "connection", (socket) =>
			# Request identification from the newly connected client
			socket.emit "id"

			# Handle gui identification response
			socket.on "ui", =>
				@ui = socket

			# Handle identification responses for clients
			socket.on "id", (id) =>
				# Update the socket for the given identifier
				@socket[id] = socket

				# If there is no saved state, update the state to off
				# Otherwise, update to the last saved state
				@update id, if not @state[id] then "off" else @state[id]

				# Acknowledge the connected client
				socket.emit "connected"

			# Handle state update requests (UI only)
			socket.on "state", =>
				socket.emit "state", [@state, @ships]

			# Handle mode change requests (UI only)
			socket.on "mode", (mode) =>
				@["mode_#{mode}"]()

			# Handle fire requests
			socket.on "fire", (id) =>
				@fire id

		# Start the web server
		@http.listen port

	update: (id, state) =>
		# Update the stored state with the given state
		@state[id] = state

		# Issue the update to the client
		if @socket[id]
			@socket[id].emit "off"
			if state != "off" then @socket[id].emit @state[id]

		# Notify the UI about the update
		@ui?.emit "update", [id, state, @ships[id]]

	broadcast_update: (state) =>
		# Update the stored states with the given state
		for id,_ of @state
			@state[id] = state

		#Issue the update to the connected clients
		@io.sockets.emit "off"
		if state != "off" then @io.sockets.emit state

		# Notify the UI about the update
		@ui?.emit "state", [@state, @ships]

	noop: (id) =>

	test_mode: (id) =>
		# Toggle between red and white for each cell to test connectivity
		# Also updates the UI for visual confirmation
		switch @state[id]
			when "white" then @update id, "red"
			else @update id, "white"

	set_ships: (id) =>
		# Figure out which team is trying to place ships
		team = parseInt id[0]

		# Ignore input from the team not placing ships
		if team == @turn[1] then return

		# Increment or decrement the ship count with toggle
		if @ships[id] then @count[team-1]-- else @count[team-1]++
		
		# Enable or disable the position as a ship
		@ships[id] = not @ships[id]

		# Notify the client and UI of the change
		@update id, if @ships[id] then "red" else "off"

	play_game: (id) =>
		console.log "SRC:  #{id}"

		# Figure out which team the player is on
		team = parseInt id[0]

		# Ignore all input from the opposite team
		if team != @turn[0] then return

		# Ignore input if you've already fired
		if @done[id] then return

		# Figure out where the shot is going
		dest = "#{if team == 1 then 2 else 1}#{id[1..]}"
		console.log "DEST: #{dest}"

		# Skip remaining sequence if the destination doesn't exist
		# (Counts as a miss)
		if not @socket[dest]
			@socket[id].emit "takeoff"
			@update dest, "white"
			@turn.reverse()
			return

		# Calculate affected doppler positions
		letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		src_col = letters.indexOf id[1]
		src_dop = [src_col+1...@cols]
		dst_dop = [0...src_col]

		# Convert indices to positions
		src_dop = ("1#{letters[s]}#{id[2]}" for s in src_dop)
		dst_dop = ("2#{letters[s]}#{id[2]}" for s in dst_dop)

		# Invert positions if firing from right to left
		# (Above assumes firing from left to right)
		if @turn[0] == 2 then [src_dop, dst_dop] = [dst_dop.reverse(), src_dop.reverse()]

		# Combine positions into a contiguous segment
		doppler = src_dop.concat dst_dop

		# Lookup if there is a ship at the destination
		result = "miss"
		if @ships[dest]
			@hits[@turn[1]-1]++;
			result = "hit"

		# Mark the source as having fired
		@done[id] = true

		# Run firing sequence commands
		@socket[id].emit "takeoff"
		for d in doppler
			if @socket[d] then @socket[d].emit "doppler"
		@socket[dest].emit result
		@update dest, if result == "hit" then "red" else "white"

		# Determine if the current team has won
		if @hits[@turn[1]-1] == @count[@turn[1]-1] 
			@winner @turn[0]
		else
			@ui.emit "turn", @turn[1]
			@turn.reverse()

	winner: (team) =>
		# Disable the firing button
		@fire = @noop

		# Notify the UI of the winning team
		@ui.emit "winner", team

		# Flash everyone's lights to indicate the game is over
		color = ((if ((i % 2) == 0) then "red" else "white") for i in [0...10])
		color.push "off"
		blink = =>
			@broadcast_update color.shift()
			if color.length > 0 then setTimeout blink, 500
		blink()

	mode_test: =>
		# Disable the firing button
		@fire = @noop

		# Setup test mode (reset state)
		@state = {}
		@ships = {}

		# Turn off all lights, and reset the UI
		@broadcast_update "off"
		
		# Reenable the firing button
		@fire  = @test_mode

	mode_ship: =>
		# Disable the firing button
		@fire = @noop

		# Setup ship mode (begin a new game)
		@ships = {}
		@count = [0, 0]
		@turn  = [1, 2]

		# Turn off all lights, and reset the UI
		@broadcast_update "off"

		# Reenable the firing button
		@fire  = @set_ships

	mode_team: =>
		# Disable the firing button
		@fire = @noop

		# Change who is placing ships
		@turn.reverse()

		# Turn off all lights, and reset the UI
		@broadcast_update "off"

		# Re-enable ship placement
		@fire = @set_ships

	mode_game: =>
		# Disable the firing button
		@fire = @noop

		# Setup game mode (play game)
		@hits = [0, 0]
		@done = {}
		
		# Randomize who goes first
		@turn = Math.floor(Math.random() * 2) + 1
		@turn = [@turn, if @turn == 1 then 2 else 1]
		console.log "Team #{@turn[0]}'s turn"
		@ui.emit "turn", @turn[0]

		# Turn off all lights, and reset the UI
		@broadcast_update "off"
		
		@fire = @play_game

exports.Ship   = Ship
exports.Player = Player