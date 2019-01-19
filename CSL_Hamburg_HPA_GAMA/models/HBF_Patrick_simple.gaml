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
	file pedestrian_paths <- file(cityGISFolder + "pedestrian_path_complex.shp");
	file boundary <- file(cityGISFolder + "Bounds.shp");
	
	file metro_lines <- file(cityGISFolder + "ambiance/Metro Lines.shp");
	file road_traffic <- file(cityGISFolder + "ambiance/Traffic.shp");
	file road_traffic_origin <- file(cityGISFolder + "ambiance/Traffic-origin.shp");
	file road_traffic_destination <- file(cityGISFolder + "ambiance/Traffic-destination.shp");
	
	file site_plan <- image_file(cityGISFolder + "Site Plan.tif");
	file tourist_icon <- image_file(cityGISFolder + "/images/Tourist.gif");
	file person_icon <- image_file(cityGISFolder + "/images/Person.gif");
	file ubahn_icon <- image_file(cityGISFolder + "/images/Ubahn.png");
	file sprinter_icon <- image_file(cityGISFolder + "/images/Sprinter.png");
	file shuttle_icon <- image_file(cityGISFolder + "/images/Shuttle.png");
		
	geometry shape <- envelope(boundary);
	graph the_graph;
	graph network;
	graph network_traffic;
	graph network_metro;
	
	float step <- 1#s;
	
	int nb_taxis <- 20;
	int nb_shuttle <- 2;
	int nb_sprinters <- 3 parameter: true;
	int nb_crew <- 2 parameter: true;
	int max_nb_people <- 200 parameter:true;
	int max_nb_tourist <- 2500 parameter:true; // this should be taken from the CSV with vessel schedules
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	int maximal_turn <- 30; //in degree
	int cohesion_factor_ppl <- 1; //must be more than 0
	int cohesion_factor_tou <- 100;
	float people_size <- 1.0;
	int coming_train;
	int schedule;
	float perception_distance <- 100.0 parameter: true; //Gehl social field of vision
	
	float train_freq <- 1.0 parameter: true;
	int current_hour <- 5;
	int current_day;
	int nb_tourist;
	int nb_people;

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
		coming_train <- rnd(8); //trains arriving every hour to one platform 1 to 8.
		nb_tourists <- length(tourist);
		nb_tourists_dropping_luggage <- tourist count each.dropping_now;
		nb_tourists_to_drop_off <- tourist count (each.knows_where_to_go and not each.dropped_luggage and not each.dropping_now);
		nb_tourists_disoriented <- tourist count (not each.knows_where_to_go);
		nb_tourists_to_shuttles <- tourist count each.dropped_luggage;		
	} 
	
	reflex time_update when: every(1#hour) {
		current_hour <- current_hour +1;
		if current_hour > 23{
			current_hour <- 0;
		}
		write "Day: " + string (current_day) + " Hour: " + string(current_hour) + ":00" ;
		if current_hour mod 24 = 0{
			current_day <- current_day+1;
		}
	}
	
	reflex time_peaks { 				//need to ajust to match the activity curve on IG
		nb_tourist <- int(max_nb_tourist*0.02);
		if current_hour < 6{
			nb_people <- int(max_nb_people * 0.01);
			nb_tourist <- 0;
		}
		if current_hour > 5 and current_hour < 8{
			nb_people <- int(max_nb_people * 0.05);
			nb_tourist <- int(nb_tourist *0.05);	
		}
		if current_hour > 7 and current_hour < 12{
			nb_people <- int(max_nb_people * 0.25);
			nb_tourist <- int(nb_tourist *0.1);	
		}
		if current_hour > 11 and current_hour < 15{
			nb_people <- int(max_nb_people * 0.15);
			nb_tourist <- int(nb_tourist *0.5);	
		}
		if current_hour > 11 and current_hour < 15{
			nb_people <- int(max_nb_people * 0.15);
			nb_tourist <- int(nb_tourist *0.25);	
		}
		if current_hour > 14 and current_hour < 18{
			nb_people <- int(max_nb_people * 0.35);
			nb_tourist <- int(nb_tourist *0.1);	
		}
		if current_hour > 17 and current_hour < 24{
			nb_people <- int(max_nb_people * 0.05);
			nb_tourist <- 0;	
		}
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
		create metro from: shapefile_public_transportation with: [station:string(read("station")), number:int(read("id"))];
		create roads from: clean_network(shapefile_roads.contents, 1.0, true, true);
		create crew_spot from: crew_spots;
		create sprinter_spot from: sprinter_spots;
		the_graph <- as_edge_graph(roads);
		create dropoff_area from: shapefile_dropoff_area;
		create shuttle_spot from: shapefile_shuttle;
		create entry_points from: shapefile_entry_points with: [platform_nb::int(read("platform"))]; //number of platform taken from shapefile
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
		create metro_line from:metro_lines with: [colors::rgb(read("color"))];
		network_metro <- as_edge_graph(metro_lines) with_optimizer_type "FloydWarshall";
		create pedestrian_path from:pedestrian_paths;
		network <- as_edge_graph(pedestrian_path) with_optimizer_type "FloydWarshall";	 
		create traffic_road from:road_traffic;
		network_traffic <- as_edge_graph(traffic_road) with_optimizer_type "FloydWarshall";	
		
		create traffic_origin from:road_traffic_origin;
		create traffic_destination from:road_traffic_destination;
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

species car skills: [moving]{
	point final_target <- point(one_of(traffic_destination));
	
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}

	reflex move {
		do goto target: final_target on: network_traffic speed:50#km/#h;
	}	
	
	aspect default {
		draw circle(2) color: #gray;
	}
}

species metro_train skills: [moving]{
	point final_target;
	
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}

	reflex move {
		do goto target: final_target on: network_metro speed:50#km/#h;
	}	
	
	aspect default {
		draw circle(2) color: #gray;
	}
}

species traffic_origin{
	reflex create_cars when: every(50#cycle){
		create car number: 1 with: [location::location]{		
		}
	}
}
species traffic_destination{}
species traffic_road{} 


species roads{}
species metro_line{
	rgb colors;
	aspect default {
		draw shape color:colors width:3;
	}
}

species crew_spot{
	crew current_crew;
	list<tourist> waiting_tourists;
	aspect base {
		int i<-0;
		loop t over:waiting_tourists{
			//draw circle (1) at:{t.location.x+rnd(-3.0,3.0),t.location.y+rnd(-3.0,3.0)} color:#red ;	
			draw circle (1) at:{t.location.x+i,t.location.y+i*3} color:rgb(246,232,198) ;
			i<-i+1;	
		}
	} 
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
	aspect base {
		//draw shape /*depth:15*/ color: color; //make depth correspond to height in shapefile
		draw shape border: #white empty:true;
	}
}

species metro{
	image_file icon <- ubahn_icon;
	string station;
	int number;
	
	reflex metro_trains when: every(120 #cycle) and self.number != nil{
		create metro_train number:1 with: [location::location]{
			final_target <- point(one_of(metro where(each.number = myself.number)));
		}
	}
		
	reflex create_opeople when: every(100 #cycle) and self.number = nil{
		create people number: nb_people/10 with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(one_of(metro));
			}	
		}
		
	aspect base {
		draw icon size:8 rotate:180;
		draw station font:font("Helvetica Neue",5, #plain) color:#gray anchor:#center;
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
	
	reflex train_comes when: every(15#minute){
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
	float speed <-gauss(3,1) #km/#h min: 1.0;
	image_file icon <- person_icon;
	
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}

	reflex move {
		do goto target: final_target on: network speed:speed;
	}	
	
	aspect default {
		draw circle(1) color: rgb(246,232,198);
	}
}

species sprinter skills:[moving] control:fsm {
	point target_loc;
	int luggage_capacity <- 1000;
	image_file icon <- sprinter_icon;
	float speed <- 50 #km/#h;
	
	action depart {
		do goto target: target_loc on:the_graph speed:speed;
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
		draw circle(1) color:color;
	}
}

species tourist skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	bool dropped_luggage;
	int luggage_count <- rnd(1)+1;
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
		do goto target: final_target on: network speed:speed;
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
		do goto target: final_target on: network speed:speed;
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
			final_target <- point(one_of(shuttle_spot));
		}
		do goto target: final_target on: network speed:speed;
		if (location distance_to final_target) < 10.0  {
			do die;
		}
	}
	
	aspect default {
		draw circle(1) color: rgb(246,232,198);
	}
}

experiment "PCM_Simulation" type: gui {
	font regular <- font("Helvetica Neue", 12, # bold);

	output {
		display charts refresh:every(1#mn){
			chart "Tourist in Central Station" type: pie size:{1,0.5} position: {0,0}background: rgb(40,40,40) axes: #white color: #white legend_font:("Helvetica Neue") label_font:("Helvetica Neue") tick_font:("Helvetica Neue") title_font:("Helvetica Neue"){
				data "Disoriented tourists" value: nb_tourists_disoriented color: rgb(245,213,236);
				data "Tourists going to the luggage drop off area" value: nb_tourists_to_drop_off color: rgb(206,233,249);
				data "Tourists dropping off their luggage" value: nb_tourists_dropping_luggage color: rgb(246,232,198);
				data "Tourists going to the shuttles" value: nb_tourists_to_shuttles color: rgb(200,200,200);
				
			}
			chart "Tourist in Central Station" type: series size:{1,0.5} position: {0,0.5} background: rgb(40,40,40 ) axes: #white color: #white legend_font:("Helvetica Neue") label_font:("Helvetica Neue") tick_font:("Helvetica Neue") title_font:("Helvetica Neue"){
				data "Disoriented tourists" value: nb_tourists_disoriented color: rgb(245,213,236) marker_size:0 thickness:2;
				data "Tourists going to the luggage drop off area" value: nb_tourists_to_drop_off color: rgb(206,233,249) marker_size:0 thickness:2;
				data "Tourists dropping off their luggage" value: nb_tourists_dropping_luggage color: rgb(246,232,198) marker_size:0 thickness:2;
				data "Tourists going to the shuttles" value: nb_tourists_to_shuttles color: rgb(200,200,200) marker_size:0 thickness:2;
				data "Tourists in the station" value: nb_tourists color: rgb(150,150,150) marker_size:0 thickness:2;
			}
		}
		display map type:opengl  background: rgb(40,40,40)
		{
			image site_plan transparency:0.75;
			species metro_line aspect:default transparency:0.85;
			species hbf aspect:base;
			species metro aspect: base ;
			species shuttle_spot aspect: base ;
			species people transparency:0.7;
			species dropoff_area aspect: base transparency: 0.85;
			species tourist aspect: default trace:5 fading:true;
			//species walking_area aspect:base transparency:0.93 ;
			//species sprinter_spot aspect: default;
			species sprinter aspect: default;
			species crew aspect: default;
			species crew_spot aspect:base ;
			species car aspect:default  trace:2 fading:true;
			species metro_train aspect:default  trace:2 fading:true;
			
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
