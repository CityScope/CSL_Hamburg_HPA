/***
* Name: HBFDetail
* Author: JLopez
* Description: The model aims to represent the movement of people and tourists in the tran station and surounding area. People arrive by train and go to random destinations. Tourist arrive by train and go to (1) taxi (2) luggage dropoff area and (3) take bus shuttle.
* Tags: Tag1, Tag2, TagN
***/

model HBFDetail

global {
	string cityGISFolder <- "./../external/";
	file shapefile_hbf <- file(cityGISFolder + "Hbf-Detail.shp");
	file shapefile_walking_paths <- file(cityGISFolder + "Detail_Walking Areas.shp");
	file shapefile_public_transportation <- file(cityGISFolder + "Detail_Public Transportation.shp");
	file shapefile_dropoff_area <- file(cityGISFolder + "Dropoffarea.shp");
	file shapefile_shuttle <- file(cityGISFolder + "Detail_Bus Shuttle.shp");
	file shapefile_entry_points <- file(cityGISFolder + "Detail_Entry Points Platforms.shp");
	file shapefile_roads <- file(cityGISFolder + "Detail_Road.shp");
	geometry shape <- envelope(shapefile_walking_paths);
	graph the_graph;
	float step <- 1 #s;
	int current_hour update: (time / #hour) mod 24;
	
	int nb_taxis <- 20;
	int nb_shuttle <- 2;
	int nb_sprinters <- rnd(2)+1;
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	int maximal_turn <- 30; //in degree
	int cohesion_factor_ppl <- 1; //must be more than 0
	int cohesion_factor_tou <- 100;
	float people_size <- 1.0;
	int coming_train;
	int nb_people_existing;
	int luggage_drop<-0;
	
	float perception_distance <- 600.0;
	int precision <- 120;
	
	reflex update { 
		coming_train <- rnd(500)+rnd(700); //trains arriving randomly
		nb_people_existing <- length(list(people));
		luggage_drop <- int(tourist count(each.dropped_luggage));
	}

	init{			
		create hbf from: shapefile_hbf;
		create metro from: shapefile_public_transportation;
		create roads from: shapefile_roads;
		the_graph <- as_edge_graph(list(roads));
		
		create dropoff_area from: shapefile_dropoff_area;
		create shuttle_spot from: shapefile_shuttle;
		create entry_points from: shapefile_entry_points with: [platform_nb::int(read("platform_s"))]; //number of platform should be taken from shapefile
		create walking_area from: shapefile_walking_paths {
			//Creation of the free space by removing the shape of the buildings (train station complex)
			free_space <- geometry(walking_area);
		}
		free_space <- free_space simplification(1.0);
		create sprinter number:nb_sprinters {
			location <- any_location_in(one_of(roads));
		}
	}
}
species roads{}

species hbf{
	rgb color <- #gray;	
	aspect base {
		draw shape color: color;
	}
}

species metro{
	rgb color <- #red;	
	aspect base {
		draw square(4) color: color;
	}
}

species dropoff_area{
	rgb color <- #white;
	bool has_sprinter;
	
	reflex with_sprinter {
		list<sprinter> inside <- sprinter inside (self);
		if length(inside) > 0{
			has_sprinter<-true;
		}
	}
	
	aspect base {
		draw shape;
	}
}

species shuttle_spot{
	rgb color <- #blue;	
	aspect base {
		draw square(4) color: color;
	}
}

species entry_points{
	rgb color<-#black;	
	bool has_train <- false;
	int platform_nb;
	
	reflex train {
		if (coming_train = platform_nb) {
			has_train <- true;
			
			create species(people) number: rnd(3){
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				target_loc <- point(one_of(metro));
				location <- point(myself);
			}	
			create species(tourist) number: rnd(2){
			speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			target_loc <- point(one_of(sprinter));
			location <- point(myself);
			luggage_count <- rnd(3)+1;
			}	
		}
	}	
	
	aspect base {
		draw square(4) color: color;
	}
}

species walking_area{
	rgb color <- #pink;	
	aspect base {
		draw shape color: color;
	}
}

species people skills:[moving] {
	point target_loc;
	float size <- people_size; 
	rgb color <- #black;
	
	reflex end when: location distance_to target_loc <= 5 * people_size{
		do die;
	}

	reflex move {
		do goto target: target_loc on:(geometry(walking_area));
		if not(self overlaps free_space) {
			location <- ((location closest_points_with free_space)[1]);
		}
	}	
	
	aspect default {
		draw circle(size) color: color;
	}
}

species sprinter skills:[moving] control:fsm {
	point target_loc;
	int luggage_capacity;
	
	action depart {
		do goto target: target_loc on:the_graph; ///////////////////////////////Import roads and make them drive on them to Terminals
	}
	
	state empty initial:true {
		luggage_capacity <- 5;
		color<- #green;
		target_loc <- any_location_in(one_of(dropoff_area));
		transition to: loading when: (location distance_to one_of(dropoff_area)) <1;
		do depart;
	}
	
	state loading{
		color<- #orange;
		transition to: full when: luggage_capacity < 1;
	}
	
	state full {
		color <- #red;
		target_loc <- point(one_of(shuttle_spot));////////// This should represent the terminals
		do depart;
		transition to: empty when: (location distance_to target_loc <5);
	}
	
	aspect default {
		draw square(4) color: color;
	}
}

species tourist skills:[moving] control:fsm {
	point target_loc <- (point(one_of(sprinter where(each.state = 'loading'))));///////////////////////////////define how they wait in the line
	float speed <- 5 + rnd(1000) / 1000;
	point velocity <- {0,0};
	float heading max: heading + maximal_turn min: heading - maximal_turn;
	float size <- people_size; 
	rgb color <- #orange;
	bool dropped_luggage;
	bool knows_where_to_go;
	geometry perceived_area;
	point target;
	int luggage_count;
		
	//Reflex to change target when arrived
	reflex drop_off when: location distance_to target_loc <= 2 * people_size and dropped_luggage = false{
		target_loc <- point(one_of(shuttle_spot));
		dropped_luggage <- true;
		knows_where_to_go <- true;
		write luggage_count;
		ask one_of(sprinter){
			luggage_capacity <- luggage_capacity - myself.luggage_count; ///////////////////////////////////////////////select only one sprinter
		}
		luggage_count <- 0;
		
		write "luggage dropped";
	}
	reflex board when: location distance_to target_loc <= 2 * people_size and dropped_luggage = true{
		write "bus shuttle taken";
		do die;
	}
	//Reflex to compute the velocity of the agent considering the cohesion factor
	reflex follow_goal  {
		velocity <- velocity + ((target - location) / cohesion_factor_tou);
	}
	
	//If they perceive the drop_off area, they go there. If they don't, they keep looking for it.
	action go {
		if knows_where_to_go = true {
			point old_location <- copy(location);
			do goto target: target_loc on: (free_space);
			if not(self overlaps free_space ) {
			location <- ((location closest_points_with free_space)[1]);
			}
			velocity <- location - old_location;
		}
	}
	
	action look_for { 
		if (target_loc intersects perceived_area) {
			knows_where_to_go <- true;
		} else {
			point old_location <- copy(location);
			do goto target: (any_location_in(perceived_area intersection geometry(walking_area))) on: (free_space);
			if not(self overlaps free_space ) {
			location <- ((location closest_points_with free_space)[1]);
			}
		}
	}	
	
	state found{
		enter{
			knows_where_to_go <- true;
			perceived_area <- nil;
		}
		do go;
	}
	
	state looking_for initial: true {
		do look_for;
		do update_perception;
		transition to: found when: knows_where_to_go = true;
	}
	
	//Computation of the perceived area
	action update_perception {
		//Perception cone (amplitude 60° and max distance)
		perceived_area <- (cone(heading-30,heading+30) intersection world.shape) intersection circle(perception_distance); 
		
		//Compute the visible area from the perceived area according to the obstacles
		if (perceived_area != nil) {
			perceived_area <- perceived_area masked_by (hbf,precision); //////////////////////////////////////////THERE'S AN ERROR HERE BUT ONLY SOMETIMES
		}
	}
	
	aspect default {
		draw circle(size) color: color;
	}
	aspect perception {
		if (perceived_area != nil) {
			draw perceived_area color: #magenta;
			}
	}
}

experiment "PCM_Simulation" type: gui {
	font regular <- font("Helvetica", 14, # bold);
	output {
		display graph refresh:every(1#mn){
			chart "tourist in the city" type: series size:{1,0.5} position: {0,0} {
				data "Drop off luggage" value: luggage_drop color: #orange;
				data "People in the station" value: nb_people_existing color: #black;
			}
		}
		display map type:java2D 
		{
			species hbf aspect:base;
			species metro aspect: base ;
			species shuttle_spot aspect: base ;
			species people;
			species tourist aspect: default;
			species tourist aspect: perception transparency:0.97;
			species walking_area aspect:base transparency:0.9 ;
			species sprinter aspect: default;
		}
	}
}
