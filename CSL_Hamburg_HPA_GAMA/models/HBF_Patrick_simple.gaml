/***
* Name: HBFDetail
* Author: P. Taillandier from JLopez's model 
* Description: simple model, that uses the moving skill - no accounting of people collision
***/


/***
INDEXES
Amount of people disoriented
Average waiting time at welcome center
Amount of people queuing at welcome center
Average delay welcome center - bus shuttle
Amount of people on the way to the bus
***/

model HBFDetail

global {
	string cityGISFolder <- "/external/hbf-model/";
	string Intervention <- "/external/hbf-model/Intervention/";
	string Scenario <- "/external/hbf-model/" among:["/external/hbf-model/","/external/hbf-model/Intervention/"] parameter:"Scenario" category:"Infrastructure and service";
	
	file shapefile_hbf <- file(cityGISFolder + "Hbf-Detail.shp");
	file shapefile_walking_paths <- file(cityGISFolder + "Detail_Walking Areas.shp");
	file shapefile_public_transportation <- file(cityGISFolder + "Detail_Public Transportation.shp");
	file shapefile_entry_points <- file(cityGISFolder + "Detail_Entry Points Platforms.shp");
	file<geometry> shapefile_roads <- shape_file(cityGISFolder + "Detail_Road.shp");
	file pedestrian_paths <- file(cityGISFolder + "pedestrian_path_complex.shp");
	file boundary <- file(cityGISFolder + "Bounds.shp");
	
	file crew_spots <- file(Scenario + "crew_spots.shp");
	file sprinter_spots <- file(Scenario + "sprinter_spots.shp");
	file shapefile_shuttle <- file(Scenario + "Detail_Bus Shuttle.shp");
		file intervention_plan <- image_file(Scenario + "Intervention_modified.tif");

	file metro_lines <- file(cityGISFolder + "ambiance/Metro Lines.shp");
	/*file road_traffic <- file(cityGISFolder + "ambiance/Traffic.shp");
	file road_traffic_origin <- file(cityGISFolder + "ambiance/Traffic-origin.shp");
	file road_traffic_destination <- file(cityGISFolder + "ambiance/Traffic-destination.shp");*/
	
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
	
	float step <- 2#s;
	
	int nb_taxis <- 20;
	int nb_sprinters <- 3;
	int people_in_station;
	int cruise_size; // this should be taken from the CSV with vessel schedules
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	float people_size <- 1.0;
	int coming_train;
	float perception_distance; //Gehl social field of vision
	
	float train_freq;
	int current_hour <- 7; //starting hour of the simulation
	int current_day;
	int nb_tourist;
	int init_nb_tourist <- int(cruise_size*(hamburg_arrival_choice/100));
	int nb_people;
	float terminal_arrival_choice;
	float hamburg_arrival_choice;

	int nb_tourists update: length(tourist);
	int nb_tourists_dropping_luggage update: tourist count each.dropping_now;
	int nb_tourists_to_drop_off update: tourist count (each.knows_where_to_go and not each.dropped_luggage and not each.dropping_now);
	int nb_tourists_disoriented update: tourist count (not each.knows_where_to_go);
	int nb_tourists_to_shuttles update: tourist count each.dropped_luggage;
	int avg_waiting_time update: tourist sum_of(each.waiting_time_dropoff);
	
/////////User interaction starts here
	list<shuttle_spot> moved_agents ;
	point target;
	geometry zone <- circle(10);
	bool can_drop;
	
/////////User interaction ends here
	
	reflex update { 
		coming_train <- rnd(8); //trains arriving every hour to one platform 1 to 8.
		nb_tourists <- length(tourist);	
		nb_tourists_dropping_luggage <- tourist count each.dropping_now + tourist_shuttle count each.dropping_now;
		nb_tourists_to_drop_off <- tourist count (each.knows_where_to_go and not each.dropped_luggage and not each.dropping_now) + tourist_shuttle count (each.knows_where_to_go and not each.dropped_luggage and not each.dropping_now);
		nb_tourists_disoriented <- tourist count (not each.knows_where_to_go) + tourist_shuttle count (not each.knows_where_to_go);
		nb_tourists_to_shuttles <- tourist count each.dropped_luggage + tourist_shuttle count each.dropped_luggage;
		avg_waiting_time <- tourist sum_of(each.waiting_time_dropoff);
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
	
	reflex time_peaks { 				//adjusted to IG activeness curve
		if current_hour < 7{
			nb_people <- int(people_in_station * 0.01);
			nb_tourist <- 0;
		}
		if current_hour = 7 {
			nb_people <- int(people_in_station * 0.02);
			nb_tourist <- 0;	
		}
		if current_hour = 8{
			nb_people <- int(people_in_station * 0.05);
			nb_tourist <- int(init_nb_tourist *0.08);	
		}
		if current_hour = 9{
			nb_people <- int(people_in_station * 0.1);
			nb_tourist <- int(init_nb_tourist *0.1);	
		}
		if current_hour = 10{
			nb_people <- int(people_in_station * 0.1);
			nb_tourist <- int(init_nb_tourist *0.08);	
		}
		if current_hour = 11{
			nb_people <- int(people_in_station * 0.06);
			nb_tourist <- int(init_nb_tourist *0.1);	
		}
		if current_hour = 12{
			nb_people <- int(people_in_station * 0.05);
			nb_tourist <- int(init_nb_tourist *0.12);	
		}
		if current_hour = 13{
			nb_people <- int(people_in_station * 0.05);
			nb_tourist <- int(init_nb_tourist *0.1);	
		}
		if current_hour = 14{
			nb_people <- int(people_in_station * 0.08);
			nb_tourist <- int(init_nb_tourist *0.1);	
		}
		if current_hour = 15{
			nb_people <- int(people_in_station * 0.06);
			nb_tourist <- int(init_nb_tourist *0.08);	
		}
		if current_hour = 16{
			nb_people <- int(people_in_station * 0.08);
			nb_tourist <- int(init_nb_tourist *0.06);	
		}
		if current_hour = 17{
			nb_people <- int(people_in_station * 0.1);
			nb_tourist <- int(init_nb_tourist *0.04);	
		}
		if current_hour > 18 and current_hour < 23{
			nb_people <- int(people_in_station * 0.07);
			nb_tourist <- 0;	
		}
		if current_hour > 22{
			nb_people <- int(people_in_station * 0.05);
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
		create crew_spot from:crew_spots;
		create sprinter_spot from: sprinter_spots;
		the_graph <- as_edge_graph(roads);
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
		create shuttle from:shapefile_shuttle;
		create crew from: crew_spots {
			spot <- one_of(crew_spot where (each.current_crew = nil));
			spot.current_crew <- self;
			location <- spot.location;
		}
		create metro_line from:metro_lines with: [colors::rgb(read("color"))];
		network_metro <- as_edge_graph(metro_lines) with_optimizer_type "FloydWarshall";
		create pedestrian_path from:pedestrian_paths;
		network <- as_edge_graph(pedestrian_path) with_optimizer_type "FloydWarshall";	 
		/*create traffic_road from:road_traffic;
		network_traffic <- as_edge_graph(traffic_road) with_optimizer_type "FloydWarshall";	
		
		create traffic_origin from:road_traffic_origin;
		create traffic_destination from:road_traffic_destination;*/
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
/* 
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
*/

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
	/*
	reflex metro_trains when: every(120 #cycle) and self.number != nil{
		create metro_train number:1 with: [location::location]{
			final_target <- point(one_of(metro where(each.number = myself.number)));
		}
	}*/
		
	reflex create_opeople when: every(5+rnd(5) #mn){
		create people number: nb_people*0.1 with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(one_of(metro));
			}
		create people number: nb_people*0.01 with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(any_location_in(geometry(walking_area)));
			}	
		} 
		
	aspect base {
		draw icon size:8 rotate:180;
		draw station font:font("Helvetica Neue",5, #plain) color:#gray anchor:#center;
	}
}

species shuttle_spot control:fsm {
	crew current_crew;
	rgb color <- #blue;	
	image_file icon <- shuttle_icon;
	list<tourist_shuttle> waiting_tourists;

	state unavailable {
		transition to: available when: location distance_to one_of(shuttle) >= 1;
	}
	
	state available initial:true{
		transition to:unavailable when: location distance_to one_of(shuttle) < 1;
	}
	
	
////////////User interaction starts here
	point difference <- { 0, 0 };
	reflex r {
		if (!(moved_agents contains self)){}
	}
////////////User interaction ends here
	aspect base {
		draw circle(8) color:rgb(200,200,100);
		int i<-0;
		loop t over:waiting_tourists{
			//draw circle (1) at:{t.location.x+rnd(-3.0,3.0),t.location.y+rnd(-3.0,3.0)} color:#red ;	
			draw circle (1) at:{t.location.x+i,t.location.y+i*3} color:rgb(246,232,198) ;
			i<-i+1;	
	
		}
	}
}

species shuttle skills:[moving] control:fsm {
	rgb color <- #blue;	
	image_file icon <- shuttle_icon;
	int luggage_capacity <- 100;
	int tourist_capacity <- 50;
	float speed <- 10 #km/#h;
	point target_loc;
	
	action depart {
		do goto target: target_loc on:the_graph speed:speed;
	}
	
	state empty {
		enter {
			luggage_capacity <- 100;
			tourist_capacity <- 50;
			target_loc <- point(one_of(shuttle_spot where (each.state = 'available')));
		}
		do depart;
		transition to: loading when: (location distance_to target_loc) <1;
		
	}
	
	state loading initial:true {
		transition to: full when: luggage_capacity < 1 or tourist_capacity < 1;
	}
	
	state full {
		enter {
			target_loc <- one_of(sprinter_spot).location;
		}
		do depart;
		transition to: empty when: (location distance_to target_loc <5);
	}

	aspect base {
		draw icon size:40 rotate: my heading;
	}
}


species entry_points{
	int platform_nb;
	
	reflex train_comes when: every((1/train_freq)#hour){
		if (coming_train = platform_nb) {
	
			create people number: nb_people/train_freq with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(one_of(metro));
			}
			create tourist number: ((nb_tourist/train_freq)*(terminal_arrival_choice/100)) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			}	
			create tourist_shuttle number: ((nb_tourist/train_freq)*(1-terminal_arrival_choice/100)) with: [location::location]{
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
	float speed <-gauss(3,2) #km/#h min: 1.0;
	image_file icon <- person_icon;
	
	reflex end when: (location distance_to final_target) <= 15{
		do die;
	}

	reflex move {
		do goto target: final_target on: network speed:speed;
	}	
	
	aspect default {
		draw circle(1) color: rgb(100,100,100);
	}
}

species sprinter skills:[moving] control:fsm {
	point target_loc;
	int luggage_capacity;
	image_file icon <- sprinter_icon;
	float speed <- 10 #km/#h;
	
	action depart {
		do goto target: target_loc on:the_graph speed:speed;
	}
	
	state empty initial:true {
		enter {
			luggage_capacity <- 50;
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
	shuttle current_shuttle;
	int start_waiting_time_dropoff;
	int end_waiting_time_dropoff;
	int waiting_time_dropoff;
	
	reflex waiting_time{
		waiting_time_dropoff<-end_waiting_time_dropoff-start_waiting_time_dropoff;
		if waiting_time_dropoff < 0 {
			waiting_time_dropoff<-0;
		}
	}
	
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
			start_waiting_time_dropoff <- cycle;
			the_spot.waiting_tourists << self;
			dropping_now <- true;
		}
		transition to: go_to_the_bus when: dropped_luggage;
	}
	state go_to_the_bus {
		enter {
			end_waiting_time_dropoff <- cycle;
			dropping_now <- false;
			final_target <- point(one_of(shuttle_spot));
		}
		do goto target: final_target on: network speed:speed;
		if (location distance_to final_target) < 10.0  {
			current_shuttle <- shuttle closest_to self;	
			current_shuttle.tourist_capacity <- current_shuttle.tourist_capacity - 1;
			do die;
		}
	}
	
	aspect default {
		draw circle(1.5) color: #white;
	}
}

species tourist_shuttle skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	bool dropped_luggage;
	int luggage_count <- 2;
	bool dropping_now <- false;
	float waiting_time;
	int tourist_line;
	image_file icon <- tourist_icon;
	shuttle_spot the_spot;
	list<shuttle_spot> known_boarding_areas;
	point final_target;
	bool knows_where_to_go <- false;
	shuttle current_shuttle;
	
	state search_drop_off_luggage initial: true{
		if (final_target = nil) {
			final_target <- any_location_in(free_space);
		}
		do goto target: final_target on: network speed:speed;
		if (self distance_to final_target < 5.0) {
			final_target <- nil;
		}
		known_boarding_areas <- known_boarding_areas + (shuttle_spot at_distance (perception_distance*2));
		transition to: goto_drop_off_luggage when: not empty(known_boarding_areas);
	}
	
	state goto_drop_off_luggage {
		enter {
			the_spot <- one_of(known_boarding_areas); 
			final_target <- the_spot.location;
			knows_where_to_go <- true;
		}
		do goto target: final_target on: network speed:speed;
		transition to: board_the_bus when: (self distance_to final_target) < 2.0;
	}
	
	state board_the_bus  {
		if (location distance_to final_target) < 2.0  {
			current_shuttle <- shuttle closest_to self;	
			current_shuttle.tourist_capacity <- current_shuttle.tourist_capacity - 1;
			do die;
		}
	}
	
	aspect default {
		draw circle(1.5) color: #white;
	}
}



experiment "PCM_Simulation" type: gui {
	float minimum_cycle_duration <- 0.02;
	font regular <- font("Helvetica Neue", 12, # bold);
	parameter "Number of passengers" var: cruise_size init:2000 min:1 max:4500 category:"Amount of people";
	parameter "People in the station" var: people_in_station init:1000 min:1 max: 2000 category: "Amount of people";
	parameter "Frequency of trains (Fractions of hour)" var: train_freq init:4.0 min:0.1 max:4.0 category: "Amount of people";
	parameter "Size of welcome center" var: nb_sprinters init:3 min:1 max: 5 category: "Infrastructure and service";
	parameter "Perception of info" var: perception_distance init:250.0 min:1.0 max:10000.0 category: "Infrastructure and service";
	parameter "% of tourists using welcome center" init:80.0 var:terminal_arrival_choice min:1.0 max:100.0 category:"Behavioral profile";
	parameter "% of tourists arriving in HH by train" init:20.0 var:hamburg_arrival_choice min:1.0 max:100.0 category: "Behavioral profile";

	output {
		display charts refresh:every(5#mn){
			chart "Tourist in Central Station" type: pie size:{1,0.5} position: {0,0}background: rgb(40,40,40) axes: #white color: #white legend_font:("Helvetica Neue") label_font:("Helvetica Neue") tick_font:("Helvetica Neue") title_font:("Helvetica Neue"){
				data "Disoriented tourists" value: nb_tourists_disoriented color: rgb(245,213,236);
				data "Tourists going to the luggage drop off area" value: nb_tourists_to_drop_off color: rgb(206,233,249);
				data "Tourists dropping off their luggage" value: nb_tourists_dropping_luggage color: rgb(246,232,198);
				data "Tourists going to the shuttles" value: nb_tourists_to_shuttles color: rgb(200,200,200);
			}
			chart " " type: series size:{0.5,0.5} position: {0,0.5} background: rgb(40,40,40 ) axes: #white color: #white legend_font:("Helvetica Neue") label_font:("Helvetica Neue") tick_font:("Helvetica Neue") title_font:("Helvetica Neue"){
				data "Disoriented tourists" value: nb_tourists_disoriented color: rgb(245,213,236) marker_size:0 thickness:2;
				data "Tourists going to the luggage drop off area" value: nb_tourists_to_drop_off color: rgb(206,233,249) marker_size:0 thickness:2;
				data "Tourists in the area" value: nb_tourists color: rgb(150,150,150) marker_size:0 thickness:2;
			}
			chart " " type: series size:{0.5,0.5} position: {0.5,0.5} background: rgb(40,40,40 ) axes: #white color: #white legend_font:("Helvetica Neue") label_font:("Helvetica Neue") tick_font:("Helvetica Neue") title_font:("Helvetica Neue"){
				data "Tourists dropping off their luggage" value: nb_tourists_dropping_luggage color: rgb(246,232,198) marker_size:0 thickness:2;
				data "Tourists going to the shuttles" value: nb_tourists_to_shuttles color: rgb(200,200,200) marker_size:0 thickness:2;
			}
		}
		display map type:opengl  background: rgb(40,40,40)
		{
			image site_plan transparency:0.75;
			image intervention_plan position:{500,300};	
			
			species metro_line aspect:default transparency:0.85 refresh:false;
			species hbf aspect:base refresh:false;
			species metro aspect: base refresh:false;
			species shuttle_spot aspect: base ;
			species people transparency:0.5;
			species tourist aspect: default trace:5 fading:true;
			//species walking_area aspect:base transparency:0.93 ;
			//species sprinter_spot aspect: default;
			species sprinter aspect: default;
			species crew aspect: default;
			species crew_spot aspect:base ;
			species tourist_shuttle aspect: default trace:5 fading:true;
			species shuttle aspect: base;
			//species car aspect:default  trace:2 fading:true;
			//species metro_train aspect:default  trace:2 fading:true;
			
			overlay position: { 5, 5 } size: { 240 #px, 680 #px } background: # black transparency: 1.0 border: #black  {
                rgb text_color<-#white;
                float y <- 12#px;
  				draw "Agents in the simulation" at: { 10#px, y } color: text_color font: font("Helvetica Neue", 12, #bold) perspective:true;
                y <- y + 10 #px;
                draw circle(3#px) at: { 10#px, y +4#px } color: rgb(100,100,100);
                draw circle(3#px) at: { 13#px, y +4#px } color: rgb(160,160,160);
                draw circle(3#px) at: { 16#px, y +4#px } color: #white;
                draw "Cruise Tourist" at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #plain) perspective:true;
				y <- y + 14 #px;
                draw circle(2#px) at: { 13#px, y +4#px } color: rgb(100,100,100);
                draw "People" at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #plain) perspective:true;
                y <- y + 14#px;
                draw circle(3#px) at: { 13#px, y +4#px } color: #pink;
                draw "Luggage Sprinter" at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #plain) perspective:true;
                y <- y + 14#px;
                draw circle(6) at: { 13#px, y +4#px } color:rgb(200,200,100);
                draw "Bus Shuttle [interaction]" at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #plain) perspective:true;
                y <- y + 14 #px;
                draw "_____________________________"at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #bold) perspective:true;
                y <- y + 21 #px;
				draw "Waiting time at welcome center" at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(avg_waiting_time/15, 8#px) at: { 0#px, y +4#px } color:#pink;
                y <- y + 14 #px;
                draw "Drop-off line length" at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_dropping_luggage*10, 8#px) at: { 0#px, y +4#px } color:#white;
                y <- y + 14 #px;
                draw "Expected people arriving to welcome center" at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_to_drop_off*10, 8#px) at: { 0#px, y +4#px } color:rgb(206,233,249);
                y <- y + 14 #px;
                draw "Disoriented" at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_disoriented*10, 8#px) at: { 0#px, y +4#px } color:rgb(246,232,198);
                y <- y + 14 #px;
                draw "On the way to bus shuttle" at: { 25#px, y + 8#px } color: text_color font: font("Helvetica Neue", 10, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_to_shuttles*10, 8#px) at: { 0#px, y +4#px } color:#gray;
                y <- y + 14 #px;         
            }
			
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
