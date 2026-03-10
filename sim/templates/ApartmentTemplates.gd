extends Node
class_name ApartmentTemplates


static func small_apartment() -> Dictionary:

	return {
		"rooms":[
			{ "id":0, "name":"Salon", "kind":"salon", "vol":60.0 },
			{ "id":1, "name":"Cocina", "kind":"cocina", "vol":30.0 },
			{ "id":2, "name":"Pasillo", "kind":"pasillo", "vol":18.0 },
			{ "id":3, "name":"Dormitorio1", "kind":"dormitorio", "vol":36.0 },
			{ "id":4, "name":"Dormitorio2", "kind":"dormitorio", "vol":32.0 },
			{ "id":5, "name":"Baño", "kind":"bano", "vol":14.0 }
		],

		"doors":[
			[0,2],
			[1,2],
			[3,2],
			[4,2],
			[5,2]
		]
	}
