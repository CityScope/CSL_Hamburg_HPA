/***
* Name: HBFDetail
* Author: P. Taillandier from JLopez's model 
* Description: simple model, that uses the moving skill - no accounting of people collision
***/

model HBFDetail

global {
	string cityGISFolder <- "/external/hbf-model/";
	file shapefile_hbf <- file(cityGISFolder + "Hbf-Detail.shp");
	file shapefile_walking_paths <- file(cityGISFolder + "Detail_Walking Areas.shp");
	file shapefile_public_transportation <- file(cityGISFolder + "Detail_Public Transportation.shp");
	file shapefile_dropoff_area <- file(cityGISFolder + "Dropoffarea.shp");
	file shapefile_shuttle <- file(cityGISFolder + "Detail_Bus Shuttle.shp");
	file shapefile_entry_points <- file(cityGISFolder + "Detail_Entry Points Platforms.shp");
	file<geometry> shapefile_roads <- shape_file(cityGISFolder + "Detail_Road.shp");
	file crew_spots <- file(cityGISFolder + "crew_spots.shp");
	file sprinter_spots <- file(cityGISFolder + "sprinter_spots.shp");
	file pedestrian_paths <- file(cityGISFolder + "pedestrian_path.shp");
	
	file tourist_icon <- image_file(cityGISFolder + "/images/Tourist.gif");
	file person_icon <- image_file(cityGISFolder + "/images/Person.gif");
	file ubahn_icon <- image_file(cityGISFolder + "/images/Ubahn.png");
	file sprinter_icon <- image_file(cityGISFolder + "/images/Sprinter.png");
	file shuttle_icon <- image_file(cityGISFolder + "/images/Shuttle.png");
		
	geometry shape <- envelope(shapefile_walking_paths);
	graph the_graph;
	graph network;
	
	float step <- 1#s;
	
	int nb_taxis <- 20;
	int nb_shuttle <- 2;
	int nb_sprinters <- 2 parameter: true;
	int nb_crew <- 2 parameter: true;
	int nb_people <- 25 parameter:true;
	int nb_tourist <- 4 parameter:true;
	
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	int maximal_turn <- 30; //in degree
	int cohesion_factor_ppl <- 1; //must be more than 0
	int cohesion_factor_tou <- 100;
	float people_size <- 1.0;
	int coming_train;
	int schedule;
	float perception_distance <- 600.0 parameter: true;
	
	float train_freq <- 1.0 parameter: true;

	int nb_tourists update: length(tourist);
	int nb_tourists_dropping_luggage update: tourist count each.dropping_now;
	int nb_tourists_to_drop_off update: tourist count (each.knows_where_to_go and not each.dropped_luggage and not each.dropping_now);
	int nb_tourists_disoriented update: tourist count (not each.knows_where_to_go);
	int nb_tourists_to_shuttles update: tourist count each.dropped_luggage;
	
/////////User interaction starts here
	list<shuttle_spot> moved_agents ;
	point target;
	geometry zone <- circle(10);
	bool can_drop;
	
/////////User interaction ends here
	
	reflex update { 
		schedule <- cycle +1; //no trainss arriving the first hour
		if (schedule mod (3600*train_freq) = 0){
			coming_train <- rnd(8); //trains arriving every hour to one platform 1 to 8.
		} else {
			coming_train <- 0;
		}
		nb_tourists <- length(tourist);
		nb_tourists_dropping_luggage <- tourist count each.dropping_now;
		nb_tourists_to_drop_off <- tourist count (each.knows_where_to_go and not each.dropped_luggage and not each.dropping_now);
		nb_tourists_disoriented <- tourist count (not each.knows_where_to_go);
		nb_tourists_to_shuttles <- tourist count each.dropped_luggage;
		
	} 
	
/////////User interaction starts here
	action kill {
		ask moved_agents{
			do die;
		}
		moved_agents <- list<shuttle_spot>([]);
	}

	action duplicate {
		geometry available_space <- (zone at_location target) - (union(moved_agents) + 10);
		create shuttle_spot number: length(moved_agents) with: (location: any_location_in(available_space));
	}

	action click {
		if (empty(moved_agents)){
			list<shuttle_spot> selected_agents <- shuttle_spot inside (zone at_location #user_location);
			moved_agents <- selected_agents;
			ask selected_agents{
				difference <- #user_location - location;
				color <- # olive;
			}
		} else if (can_drop){
			ask moved_agents{
				color <- # red;
			}
			moved_agents <- list<shuttle_spot>([]);
		}
	}

	action move {
		can_drop <- true;
		target <- #user_location;
		list<shuttle_spot> other_agents <- (shuttle_spot inside (zone at_location #user_location)) - moved_agents;
		geometry occupied <- geometry(other_agents);
		ask moved_agents{
			location <- #user_location - difference;
			if (occupied intersects self){
				color <- # red;
				can_drop <- false;
			} else{
				color <- # olive;
			}
		}
	}
////////////User interaction ends here

	init{		
		create hbf from: shapefile_hbf;
		create metro from: shapefile_public_transportation;
		create roads from: clean_network(shapefile_roads.contents, 1.0, true, true);
		create crew_spot from: crew_spots;
		create sprinter_spot from: sprinter_spots;
		the_graph <- as_edge_graph(roads);
		create dropoff_area from: shapefile_dropoff_area;
		create shuttle_spot from: shapefile_shuttle;
		create entry_points from: shapefile_entry_points with: [platform_nb::int(read("platform_s"))]; //number of platform taken from shapefile
		create walking_area from: shapefile_walking_paths {
			//Creation of the free space by removing the shape of the buildings (train station complex)
			free_space <- geometry(walking_area);
		}
		
		free_space <- free_space simplification(1.0);
		create obstacle from:(shape - free_space).geometries;
		create sprinter number:nb_sprinters {
			location <- any_location_in(one_of(roads));
		}
		
		create crew number:nb_crew {
			spot <- one_of(crew_spot where (each.current_crew = nil));
			spot.current_crew <- self;
			location <- spot.location;
		}
		
		create pedestrian_path from:pedestrian_paths;
		network <- as_edge_graph(pedestrian_path) with_optimizer_type "FloydWarshall";	 	
	}
}

species pedestrian_path {
	aspect default {
		draw shape color: #black;
	}
}

species obstacle {
	geometry free_space;
}


species roads{}
species crew_spot{
	crew current_crew;
	list<tourist> waiting_tourists;
}
species sprinter_spot control:fsm{
	
	state unavailable {
		transition to: available when: location distance_to one_of(sprinter) >= 1;
	}
	
	state available initial:true{
		transition to:unavailable when: location distance_to one_of(sprinter) < 1;
	}
	
	aspect default {
		draw circle(5.0) color: #cyan;
	}
}

species hbf{
	rgb color <- #gray;	
	aspect base {
		draw shape color: color;
	}
}

species metro{
		image_file icon <- ubahn_icon;
	aspect base {
		draw icon size:8;
	}
}

species dropoff_area control: fsm{
	rgb color <- #blue;	
	bool has_sprinter;
	aspect base {
		draw shape color:color;
	}
}

species shuttle_spot{
	rgb color <- #blue;	
	image_file icon <- shuttle_icon;
	
////////////User interaction starts here
	point difference <- { 0, 0 };
	reflex r {
		if (!(moved_agents contains self)){}
	}
////////////User interaction ends here
	aspect base {
		draw icon size:40 rotate:30;
	}
}

species entry_points{
	int platform_nb;
	
	reflex train when: every(1000 #cycle){
		if (coming_train = platform_nb) {
	
			create people number: nb_people with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(one_of(metro));
			}
			create tourist number: nb_tourist with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			
			}	
		}
	}	
	
	aspect base {
		draw square(2);
	}
}

species walking_area{
	rgb color <- #gray;	
	aspect base {
		draw shape color: color;
	}
}

species people skills: [moving] {
	point final_target;
	float size <- people_size; 
	image_file icon <- person_icon;
	
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}

	reflex move {
		do goto target: final_target on: network;
	}	
	
	aspect default {
		draw icon size:3 rotate: my heading;
	}
}

species sprinter skills:[moving] control:fsm {
	point target_loc;
	int luggage_capacity <- 10;
	image_file icon <- sprinter_icon;
	
	action depart {
		do goto target: target_loc on:the_graph;
	}
	
	state empty initial:true {
		enter {
			luggage_capacity <- 10;
			target_loc <- point(one_of(sprinter_spot where (each.state = 'available')));
		}
		do depart;
		transition to: loading when: (location distance_to target_loc) <1;
		
	}
	
	state loading{
		transition to: full when: luggage_capacity < 1;
	}
	
	state full {
		enter {
			target_loc <- one_of(shuttle_spot).location;
		}
		do depart;
		transition to: empty when: (location distance_to target_loc <5);
	}
	
	aspect default {
		draw circle(6) color: #pink;
		draw icon size:7 rotate: my heading ;
	}
}

species crew skills:[moving] control:fsm {
	point target_loc;
	crew_spot spot;
	int carrying_luggage;
	tourist current_tourist;
	sprinter current_sprinter;
	rgb color <- #green;
	
	action carry_luggage{
		if ((current_sprinter = nil) or (current_sprinter.state != "loading")) {
			list<sprinter> available_sprinter <- sprinter where (each.state = 'loading');
			if not empty(available_sprinter) {
				current_sprinter <- available_sprinter closest_to self;
				target_loc <- current_sprinter.location;
			}
		}
		
		if (target_loc != nil) {
			do goto target: target_loc;
			if location distance_to target_loc < 1 {
				current_sprinter.luggage_capacity <- current_sprinter.luggage_capacity - carrying_luggage;
				carrying_luggage <- 0;
				current_sprinter <- nil;
				target_loc <- nil;
			}
		}
	}
	
	state go_back_spot {
		enter {
			color <- #yellow;
		}
		do goto target:spot;
		transition to: available  when: location = spot.location;
	}
	
	state go_to_sprinter {
		enter {
			current_tourist <- first(spot.waiting_tourists);
			remove current_tourist from: spot.waiting_tourists;
			carrying_luggage <- current_tourist.luggage_count;
			current_tourist.dropped_luggage <- true;
			current_tourist.luggage_count <- 0;
			color <- #red;
			target_loc <- nil;
		}
		do carry_luggage;
		
		transition to: go_back_spot when: carrying_luggage = 0;
	}
	
	state available initial:true{
		enter{
			color <- #green;
		}
		transition to: go_to_sprinter when: not empty(spot.waiting_tourists);
	}
	aspect default {
		draw circle(3) color:color;
	}
}

species tourist skills:[moving] control:fsm {
	float speed <-gauss(5,1) #km/#h min: 2.0;
	bool dropped_luggage;
	int luggage_count <- rnd(3)+1;
	bool dropping_now <- false;
	float waiting_time;
	int tourist_line;
	image_file icon <- tourist_icon;
	crew_spot the_spot;
	list<crew_spot> known_drop_off_areas;
	point final_target;
	bool knows_where_to_go <- false;

	
	state search_drop_off_luggage initial: true{
		if (final_target = nil) {
			final_target <- any_location_in(free_space);
		}
		do goto target: final_target on: network;
		if (self distance_to final_target < 5.0) {
			final_target <- nil;
		}
		known_drop_off_areas <- known_drop_off_areas + (crew_spot at_distance perception_distance) where (each.current_crew != nil);
		transition to: goto_drop_off_luggage when: not empty(known_drop_off_areas);
	}
	
	state goto_drop_off_luggage {
		enter {
			the_spot <- one_of(known_drop_off_areas ); 
			final_target <- the_spot.location;
			knows_where_to_go <- true;
		}
		do goto target: final_target on: network;
		transition to: drop_off_luggage when: (self distance_to final_target) < 10.0;
	}
	
	
	state drop_off_luggage {
		enter {
			the_spot.waiting_tourists << self;
			dropping_now <- true;
		}
		transition to: go_to_the_bus when: dropped_luggage;
	}
	state go_to_the_bus  {
		enter {
			dropping_now <- false;
			final_target <- point(one_of(metro));
		}
		do goto target: final_target on: network;
		if (location distance_to final_target) < 10.0  {
			do die;
		}
	}
	
	
	
	aspect default {
		draw icon size: 3 rotate: my heading;
	}

}

experiment "PCM_Simulation" type: gui {
	font regular <- font("Helvetica", 14, # bold);

	output {
		display charts refresh:every(1#mn){
			chart "tourist in the city" type: pie size:{1,0.5} position: {0,0}background: #lightgray {
				data "Disoriented tourists" value: nb_tourists_disoriented color: #red;
				data "Tourists going to the luggage drop off area" value: nb_tourists_to_drop_off color: #orange;
				data "Tourists dropping off their luggage" value: nb_tourists_dropping_luggage color: #yellow;
				data "Tourists going to the shuttles" value: nb_tourists_to_shuttles color: #green;
				
			}
			chart "tourist in the city" type: series size:{1,0.5} position: {0,0.5} background: #lightgray{
				data "Disoriented tourists" value: nb_tourists_disoriented color: #red;
				data "Tourists going to the luggage drop off area" value: nb_tourists_to_drop_off color: #orange;
				data "Tourists dropping off their luggage" value: nb_tourists_dropping_luggage color: #yellow;
				data "Tourists going to the shuttles" value: nb_tourists_to_shuttles color: #green;
				data "Tourists in the station" value: nb_tourists color: #black;
			}
		}
		display map type:java2D 
		{
			species hbf aspect:base transparency: 0.75;
			species metro aspect: base ;
			species shuttle_spot aspect: base ;
			species people;
			species dropoff_area aspect: base transparency: 0.85;
			species tourist aspect: default;
			//species tourist aspect: perception transparency:0.97;
			species walking_area aspect:base transparency:0.93 ;
			species sprinter_spot aspect: default;
			species sprinter aspect: default;
			species crew aspect: default;
		
////////////////////User interaction starts here		
			event mouse_move action: move;
			event mouse_up action: click;
			event 'r' action: kill;
			event 'c' action: duplicate;
			graphics "Full target" {
				int size <- length(moved_agents);
				if (size > 0){
					rgb c1 <- rgb(#darkseagreen, 120);
					rgb c2 <- rgb(#firebrick, 120);
					draw zone at: target empty: false border: false color: (can_drop ? c1 : c2);
					draw string(size) at: target + { -30, -30 } font: regular color: # white;
					draw "'r': remove" at: target + { -30, 0 } font: regular color: # white;
					draw "'c': copy" at: target + { -30, 30 } font: regular color: # white;
				}
			}
////////////////////User interaction ends here	
		}
	}
}
