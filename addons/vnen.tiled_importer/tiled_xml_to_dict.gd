# The MIT License (MIT)
#
# Copyright (c) 2018 George Marques
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

tool
extends Reference

# All templates loaded, can be looked up by path name
var _loaded_templates = {}
# Maps each tileset file used by the map to it's first gid; Used for template parsing
var _tileset_path_to_first_gid = {}

func reset_global_memebers():
	_loaded_templates = {}
	_tileset_path_to_first_gid = {}

# Reads a TMX file from a path and return a Dictionary with the same structure
# as the JSON map format
# Returns an error code if failed
func read_tmx(path):
	reset_global_memebers()
	var parser = XMLParser.new()
	var err = parser.open(path)
	if err != OK:
		printerr("Error opening TMX file '%s'." % [path])
		return err

	while parser.get_node_type() != XMLParser.NODE_ELEMENT:
		err = parser.read()
		if err != OK:
			printerr("Error parsing TMX file '%s' (around line %d)." % [path, parser.get_current_line()])
			return err

	if parser.get_node_name().to_lower() != "map":
		printerr("Error parsing TMX file '%s'. Expected 'map' element.")
		return ERR_INVALID_DATA

	var data = attributes_to_dict(parser)
	if not "infinite" in data:
		data.infinite = false
	data.type = "map"
	data.tilesets = []
	data.layers = []

	err = parser.read()
	if err != OK:
		printerr("Error parsing TMX file '%s' (around line %d)." % [path, parser.get_current_line()])
		return err

	while err == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "map":
				break
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
			if parser.get_node_name() == "tileset":
				# Empty element means external tileset
				if not parser.is_empty():
					var tileset = parse_tileset(parser)
					if typeof(tileset) != TYPE_DICTIONARY:
						# Error happened
						return err
					data.tilesets.push_back(tileset)
				else:
					var tileset_data = attributes_to_dict(parser)
					if not "source" in tileset_data:
						printerr("Error parsing TMX file '%s'. Missing tileset source (around line %d)." % [path, parser.get_current_line()])
						return ERR_INVALID_DATA
					_tileset_path_to_first_gid[path] = tileset_data["firstgid"]
					data.tilesets.push_back(tileset_data)

			elif parser.get_node_name() == "layer":
				var layer = parse_tile_layer(parser, data.infinite)
				if typeof(layer) != TYPE_DICTIONARY:
					printerr("Error parsing TMX file '%s'. Invalid tile layer data (around line %d)." % [path, parser.get_current_line()])
					return ERR_INVALID_DATA
				data.layers.push_back(layer)

			elif parser.get_node_name() == "imagelayer":
				var layer = parse_image_layer(parser)
				if typeof(layer) != TYPE_DICTIONARY:
					printerr("Error parsing TMX file '%s'. Invalid image layer data (around line %d)." % [path, parser.get_current_line()])
					return ERR_INVALID_DATA
				data.layers.push_back(layer)

			elif parser.get_node_name() == "objectgroup":
				var layer = parse_object_layer(parser)
				if typeof(layer) != TYPE_DICTIONARY:
					printerr("Error parsing TMX file '%s'. Invalid object layer data (around line %d)." % [path, parser.get_current_line()])
					return ERR_INVALID_DATA
				data.layers.push_back(layer)

			elif parser.get_node_name() == "group":
				var layer = parse_group_layer(parser, data.infinite)
				if typeof(layer) != TYPE_DICTIONARY:
					printerr("Error parsing TMX file '%s'. Invalid group layer data (around line %d)." % [path, parser.get_current_line()])
					return ERR_INVALID_DATA
				data.layers.push_back(layer)

			elif parser.get_node_name() == "properties":
				var prop_data = parse_properties(parser)
				if typeof(prop_data) == TYPE_STRING:
					return prop_data

				data.properties = prop_data.properties
				data.propertytypes = prop_data.propertytypes

		err = parser.read()

	return data

# Reads a TSX and return a tileset dictionary
# Returns an error code if fails
func read_tsx(path):
	var parser = XMLParser.new()
	var err = parser.open(path)
	if err != OK:
		printerr("Error opening TSX file '%s'." % [path])
		return err

	while parser.get_node_type() != XMLParser.NODE_ELEMENT:
		err = parser.read()
		if err != OK:
			printerr("Error parsing TSX file '%s' (around line %d)." % [path, parser.get_current_line()])
			return err

	if parser.get_node_name().to_lower() != "tileset":
		printerr("Error parsing TMX file '%s'. Expected 'map' element.")
		return ERR_INVALID_DATA

	var tileset = parse_tileset(parser)

	return tileset

# Parses a tileset element from the XML and return a dictionary
# Return an error code if fails
func parse_tileset(parser):
	var err = OK
	var data = attributes_to_dict(parser)
	data.tiles = {}

	err = parser.read()
	while err == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "tileset":
				break

		elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
			if parser.get_node_name() == "tile":
				var attr = attributes_to_dict(parser)
				var tile_data = parse_tile_data(parser)
				if typeof(tile_data) != TYPE_DICTIONARY:
					# Error happened
					return tile_data
				if "properties" in tile_data and "propertytypes" in tile_data:
					if not "tileproperties" in data:
						data.tileproperties = {}
						data.tilepropertytypes = {}
					data.tileproperties[str(attr.id)] = tile_data.properties
					data.tilepropertytypes[str(attr.id)] = tile_data.propertytypes
					tile_data.erase("tileproperties")
					tile_data.erase("tilepropertytypes")
				data.tiles[str(attr.id)] = tile_data

			elif parser.get_node_name() == "image":
				var attr = attributes_to_dict(parser)
				if not "source" in attr:
					printerr("Error loading image tag. No source attribute found (around line %d)." % [parser.get_current_line()])
					return ERR_INVALID_DATA
				data.image = attr.source
				if "width" in attr:
					data.imagewidth = attr.width
				if "height" in attr:
					data.imageheight = attr.height

			elif parser.get_node_name() == "properties":
				var prop_data = parse_properties(parser)
				if typeof(prop_data) != TYPE_DICTIONARY:
					# Error happened
					return prop_data

				data.properties = prop_data.properties
				data.propertytypes = prop_data.propertytypes

		err = parser.read()

	return data

func get_template(path):
	# If this template has not yet been loaded
	if not _loaded_templates.has(path):
		# IS XML
		if path.get_extension().to_lower() == "tx":
			var parser = XMLParser.new()
			var err = parser.open(path)
			if err != OK:
				printerr("Error opening TX file '%s'." % [path])
				return err
			var content = parse_template(parser, path)
			if typeof(content) != TYPE_DICTIONARY:
				# Error happened
				print("Error parsing template map file '%s'." % [path])
				return false
			_loaded_templates[path] = content

		# IS JSON
		else:
			var file = File.new()
			var err = file.open(path, File.READ)
			if err != OK:
				return err

			var content = JSON.parse(file.get_as_text())
			if content.error != OK:
				print("Error parsing JSON template map file '%s'." % [path], content.error_string)
				return content.error
			_loaded_templates[path] = content

	var dict = _loaded_templates[path]
	var dictCopy = {}
	for k in dict:
		dictCopy[k] = dict[k]

	return dictCopy

func parse_template(parser, path):
	var err = OK
	# Template root node shouldn't have attributes
	var data = {}
	var tileset_gid_increment = 0
	data.id = 0

	err = parser.read()
	while err == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "template":
				break

		elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
			if parser.get_node_name() == "tileset":
				var ts_path = remove_filename_from_path(path) + parser.get_named_attribute_value_safe("source")
				for t in _tileset_path_to_first_gid:
					if is_same_file(ts_path, t):
						tileset_gid_increment += _tileset_path_to_first_gid[t] - 1
						data.tileset = t


			if parser.get_node_name() == "object":
				var object = parse_object(parser)
				for k in object:
					data[k] = object[k]

		err = parser.read()

	if data.has("gid"):
		data["gid"] += tileset_gid_increment

	return data

# Parses the data of a single tile from the XML and return a dictionary
# Returns an error code if fails
func parse_tile_data(parser):
	var err = OK
	var data = {}
	var obj_group = {}
	if parser.is_empty():
		return data

	err = parser.read()
	while err == OK:

		if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "tile":
				return data
			elif parser.get_node_name() == "objectgroup":
				data.objectgroup = obj_group

		elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
			if parser.get_node_name() == "image":
				# If there are multiple images in one tile we only use the last one.
				var attr = attributes_to_dict(parser)
				if not "source" in attr:
					printerr("Error loading image tag. No source attribute found (around line %d)." % [parser.get_current_line()])
					return ERR_INVALID_DATA
				data.image = attr.source
				data.imagewidth = attr.width
				data.imageheight = attr.height

			elif parser.get_node_name() == "objectgroup":
				obj_group = attributes_to_dict(parser)
				for attr in ["width", "height", "offsetx", "offsety"]:
					if not attr in obj_group:
						data[attr] = 0
				if not "opacity" in data:
					data.opacity = 1
				if not "visible" in data:
					data.visible = true
				if parser.is_empty():
					data.objectgroup = obj_group

			elif parser.get_node_name() == "object":
				if not "objects" in obj_group:
					obj_group.objects = []
				var obj = parse_object(parser)
				if typeof(obj) != TYPE_DICTIONARY:
					# Error happened
					return obj
				obj_group.objects.push_back(obj)

			elif parser.get_node_name() == "properties":
				var prop_data = parse_properties(parser)
				data["properties"] = prop_data.properties
				data["propertytypes"] = prop_data.propertytypes

		err = parser.read()

	return data

# Parses the data of a single object from the XML and return a dictionary
# Returns an error code if fails
func parse_object(parser):
	var err = OK
	var data = attributes_to_dict(parser)

	if data.has("template"):
		var template_file = data["template"]
		var template_data = get_template(template_file)
		if typeof(template_data) != TYPE_DICTIONARY:
			# Error happened
			print("Error getting template for object with id " + str(data["id"]))
			return false
		# Overwrite template data with current object data
		for k in data:
			template_data[k] = data[k]
		data = template_data

		print ("AFTER TEMPLATE: ")
		for k in data:
			print(str(k) + ": " + str(data[k]))

	if not parser.is_empty():
		err = parser.read()
		while err == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == "object":
					break

			elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
				if parser.get_node_name() == "properties":
					var prop_data = parse_properties(parser)
					data["properties"] = prop_data.properties
					data["propertytypes"] = prop_data.propertytypes

				elif parser.get_node_name() == "point":
					data.point = true

				elif parser.get_node_name() == "ellipse":
					data.ellipse = true

				elif parser.get_node_name() == "polygon" or parser.get_node_name() == "polyline":
					var points = []
					var points_raw = parser.get_named_attribute_value("points").split(" ", false, 0)

					for pr in points_raw:
						points.push_back({
							"x": float(pr.split(",")[0]),
							"y": float(pr.split(",")[1]),
						})

					data[parser.get_node_name()] = points

			err = parser.read()

	for attr in ["width", "height", "x", "y", "rotation"]:
		if not attr in data:
			data[attr] = 0
	if not "type" in data:
		data.type = ""
	if not "visible" in data:
		data.visible = true

	return data

# Parses a tile layer from the XML and return a dictionary
# Returns an error code if fails
func parse_tile_layer(parser, infinite):
	var err = OK
	var data = attributes_to_dict(parser)
	data.type = "tilelayer"
	if not "x" in data:
		data.x = 0
	if not "y" in data:
		data.y = 0
	if infinite:
		data.chunks = []
	else:
		data.data = []

	var current_chunk = null
	var encoding = ""

	if not parser.is_empty():
		err = parser.read()

		while err == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == "layer":
					break
				elif parser.get_node_name() == "chunk":
					data.chunks.push_back(current_chunk)
					current_chunk = null

			elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
				if parser.get_node_name() == "data":
					var attr = attributes_to_dict(parser)

					if "compression" in attr:
						data.compression = attr.compression

					if "encoding" in attr:
						encoding = attr.encoding
						if attr.encoding != "csv":
							data.encoding = attr.encoding

						if not infinite:
							err = parser.read()
							if err != OK:
								return err

							if attr.encoding != "csv":
								data.data = parser.get_node_data().strip_edges()
							else:
								var csv = parser.get_node_data().split(",", false)

								for v in csv:
									data.data.push_back(int(v.strip_edges()))

				elif parser.get_node_name() == "tile":
					var gid = int(parser.get_named_attribute_value_safe("gid"))
					if infinite:
						current_chunk.data.push_back(gid)
					else:
						data.data.push_back(gid)

				elif parser.get_node_name() == "chunk":
					current_chunk = attributes_to_dict(parser)
					current_chunk.data = []
					if encoding != "":
						err = parser.read()
						if err != OK:
							return err
						if encoding != "csv":
							current_chunk.data = parser.get_node_data().strip_edges()
						else:
							var csv = parser.get_node_data().split(",", false)
							for v in csv:
								current_chunk.data.push_back(int(v.strip_edges()))

				elif parser.get_node_name() == "properties":
					var prop_data = parse_properties(parser)
					if typeof(prop_data) == TYPE_STRING:
						return prop_data

					data.properties = prop_data.properties
					data.propertytypes = prop_data.propertytypes

			err = parser.read()

	return data

# Parses an object layer from the XML and return a dictionary
# Returns an error code if fails
func parse_object_layer(parser):
	var err = OK
	var data = attributes_to_dict(parser)
	data.type = "objectgroup"
	data.objects = []

	if not parser.is_empty():
		err = parser.read()
		while err == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == "objectgroup":
					break
			if parser.get_node_type() == XMLParser.NODE_ELEMENT:
				if parser.get_node_name() == "object":
					data.objects.push_back(parse_object(parser))
				elif parser.get_node_name() == "properties":
					var prop_data = parse_properties(parser)
					if typeof(prop_data) != TYPE_DICTIONARY:
						# Error happened
						return prop_data
					data.properties = prop_data.properties
					data.propertytypes = prop_data.propertytypes

			err = parser.read()

	return data

# Parses an image layer from the XML and return a dictionary
# Returns an error code if fails
func parse_image_layer(parser):
	var err = OK
	var data = attributes_to_dict(parser)
	data.type = "imagelayer"
	data.image = ""

	if not parser.is_empty():
		err = parser.read()

		while err == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name().to_lower() == "imagelayer":
					break
			elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
				if parser.get_node_name().to_lower() == "image":
					var image = attributes_to_dict(parser)
					if not image.has("source"):
						printerr("Missing source attribute in imagelayer (around line %d)." % [parser.get_current_line()])
						return ERR_INVALID_DATA
					data.image = image.source

				elif parser.get_node_name() == "properties":
					var prop_data = parse_properties(parser)
					if typeof(prop_data) != TYPE_DICTIONARY:
						# Error happened
						return prop_data
					data.properties = prop_data.properties
					data.propertytypes = prop_data.propertytypes

			err = parser.read()

	return data

# Parses a group layer from the XML and return a dictionary
# Returns an error code if fails
func parse_group_layer(parser, infinite):
	var err = OK
	var result = attributes_to_dict(parser)
	result.type = "group"
	result.layers = []

	if not parser.is_empty():
		err = parser.read()

		while err == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name().to_lower() == "group":
					break
			elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
				if parser.get_node_name() == "layer":
					var layer = parse_tile_layer(parser, infinite)
					if typeof(layer) != TYPE_DICTIONARY:
						printerr("Error parsing TMX file. Invalid tile layer data (around line %d)." % [parser.get_current_line()])
						return ERR_INVALID_DATA
					result.layers.push_back(layer)

				elif parser.get_node_name() == "imagelayer":
					var layer = parse_image_layer(parser)
					if typeof(layer) != TYPE_DICTIONARY:
						printerr("Error parsing TMX file. Invalid image layer data (around line %d)." % [parser.get_current_line()])
						return ERR_INVALID_DATA
					result.layers.push_back(layer)

				elif parser.get_node_name() == "objectgroup":
					var layer = parse_object_layer(parser)
					if typeof(layer) != TYPE_DICTIONARY:
						printerr("Error parsing TMX file. Invalid object layer data (around line %d)." % [parser.get_current_line()])
						return ERR_INVALID_DATA
					result.layers.push_back(layer)

				elif parser.get_node_name() == "group":
					var layer = parse_group_layer(parser, infinite)
					if typeof(layer) != TYPE_DICTIONARY:
						printerr("Error parsing TMX file. Invalid group layer data (around line %d)." % [parser.get_current_line()])
						return ERR_INVALID_DATA
					result.layers.push_back(layer)

				elif parser.get_node_name() == "properties":
					var prop_data = parse_properties(parser)
					if typeof(prop_data) == TYPE_STRING:
						return prop_data

					result.properties = prop_data.properties
					result.propertytypes = prop_data.propertytypes

			err = parser.read()
	return result

# Parses properties data from the XML and return a dictionary
# Returns an error code if fails
func parse_properties(parser):
	var err = OK
	var data = {
		"properties": {},
		"propertytypes": {},
	}

	if not parser.is_empty():
		err = parser.read()

		while err == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == "properties":
					break
			elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
				if parser.get_node_name() == "property":
					var prop_data = attributes_to_dict(parser)
					if not (prop_data.has("name") and prop_data.has("value")):
						printerr("Missing information in custom properties (around line %d)." % [parser.get_current_line()])
						return ERR_INVALID_DATA

					data.properties[prop_data.name] = prop_data.value
					if prop_data.has("type"):
						data.propertytypes[prop_data.name] = prop_data.type
					else:
						data.propertytypes[prop_data.name] = "string"

			err = parser.read()

	return data

# Reads the attributes of the current element and return them as a dictionary
func attributes_to_dict(parser):
	var data = {}
	for i in range(parser.get_attribute_count()):
		var attr = parser.get_attribute_name(i)
		var val = parser.get_attribute_value(i)
		if val.is_valid_integer():
			val = int(val)
		elif val.is_valid_float():
			val = float(val)
		elif val == "true":
			val = true
		elif val == "false":
			val = false
		data[attr] = val
	return data

func get_filename_from_path(path):
	var substrings = path.split("/", false)
	var file_name = substrings[substrings.size() - 1]
	return file_name

func remove_filename_from_path(path):
	var file_name = get_filename_from_path(path)
	var stringSize = path.length() - file_name.length()
	var file_path = path.substr(0,stringSize)
	return file_path

func is_same_file(path1, path2):
	var file1 = File.new()
	var err = file1.open(path1, File.READ)
	if err != OK:
		return err

	var file2 = File.new()
	err = file2.open(path2, File.READ)
	if err != OK:
		return err

	var file1_str = file1.get_as_text()
	var file2_str = file1.get_as_text()

	if file1_str == file2_str:
		return true

	return false
