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
	string show_plan <- "/external/hbf-model/Intervention/" among:["/external/hbf-model/","/external/hbf-model/Intervention/"] parameter:"Show Intervention Plan" category:"Infrastructure and service";
	
	file shapefile_hbf <- file(cityGISFolder + "Hbf-Detail.shp");
	file shapefile_walking_paths <- file(cityGISFolder + "Detail_Walking Areas.shp");
	file shapefile_public_transportation <- file(cityGISFolder + "Detail_Public Transportation.shp");
	file shapefile_entry_points <- file(cityGISFolder + "Detail_Entry Points Platforms.shp");
	file<geometry> shapefile_roads <- shape_file(cityGISFolder + "Detail_Road.shp");
	file pedestrian_paths <- file(cityGISFolder + "pedestrian_path_complex.shp");
	file boundary <- file(cityGISFolder + "Bounds.shp");
	
	file shapefile_taxi_stand <- file(Scenario + "taxi_stand.shp");
	file crew_spots <- file(Scenario + "crew_spots.shp");
	file sprinter_spots <- file(Scenario + "sprinter_spots.shp");
	file shapefile_shuttle <- file(Scenario + "Detail_Bus Shuttle.shp");
	file intervention_plan <- image_file(show_plan + "Intervention_modified.tif");
	
	file metro_lines <- file(cityGISFolder + "ambiance/Metro Lines.shp");
	file metro_origin <- file(cityGISFolder + "ambiance/Metro-origin.shp");
	file<geometry> road_traffic <- shape_file(cityGISFolder + "ambiance/Traffic.shp");
	file road_traffic_origin <- file(cityGISFolder + "ambiance/Traffic-origin.shp");
	file road_traffic_destination <- file(cityGISFolder + "ambiance/Traffic-destination.shp");
	file shapefile_buildingds <- file(cityGISFolder + "ambiance/buildings.shp");
	
	file site_plan <- image_file(cityGISFolder + "Site Plan.tif");
	file shapefile_cruise_terminals <- file(Scenario + "larger_scale/Cruise_Terminals.shp");
	file shapefile_reference_hbf<- file(cityGISFolder + "larger_scale/reference_HBF.shp");
	file<geometry> path_to_terminals <- shape_file(cityGISFolder + "larger_scale/Connection to terminals.shp");
	
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
	graph terminal_flows;
	
	float step <- 2#s;
	
	int nb_sprinters <- 3;
	int people_in_station;
	int cruise_size; // this should be taken from the CSV with vessel schedules
	
	float min_speed_ppl <- 0.5 #km / #h;
	float max_speed_ppl <- 2 #km / #h;
	geometry free_space;
	int coming_train;
	float perception_distance; //Gehl social field of vision
	
	float train_freq;
	float shuttle_freq;
	int current_hour <- 7; //starting hour of the simulation
	int current_day;
	int nb_tourist;
	int init_nb_tourist <- int(cruise_size*(hamburg_arrival_choice/100));
	int nb_people;
	float terminal_arrival_choice;
	float hamburg_arrival_choice;
	string time_info;
	int people_in_terminal;
	int people_left_terminal;

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
		time_info <- "Day: " + string (current_day) + " Hour: " + string(current_hour) + ":00" ;
		if current_hour mod 24 = 0{
			current_day <- current_day+1;
		}
	}
	
	reflex time_peaks { 				//adjusted to IG activeness curve
		/*
		map<int,float> peaks_people <- create_map([7,8,9,10,11,12,13,14,15,16,17,18],[0.02,0.05,0.1,0.06,0.05,0.05,0.05,0.08,0.06,0.08,0.1,0.07]);
		if current_hour = peaks_people.keys{
			nb_people <- int(float(peaks_people.values)*people_in_station);
			}else{
			nb_people <- int(people_in_station * 0.01);	
			}
			
		map<int,float> peaks_tourists <- create_map([8,9,10,11,12,13,14,15,16,17],[0.03,0.05,0.08,0.12,0.1,0.08,0.07,0.05,0.04,0.02]);
		if current_hour = peaks_tourists.keys{
			nb_tourist <- int(float(peaks_tourists.values)*init_nb_tourist);
			}else{
			nb_tourist <- 0;	
			}*/
		
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
			nb_tourist <- int(init_nb_tourist *0.01);	
		}
		if current_hour = 9{
			nb_people <- int(people_in_station * 0.1);
			nb_tourist <- int(init_nb_tourist *0.01);	
		}
		if current_hour = 10{
			nb_people <- int(people_in_station * 0.1);
			nb_tourist <- int(init_nb_tourist *0.08);	
		}
		if current_hour = 11{
			nb_people <- int(people_in_station * 0.06);
			nb_tourist <- int(init_nb_tourist *0.12);	
		}
		if current_hour = 12{
			nb_people <- int(people_in_station * 0.05);
			nb_tourist <- int(init_nb_tourist *0.1);	
		}
		if current_hour = 13{
			nb_people <- int(people_in_station * 0.05);
			nb_tourist <- int(init_nb_tourist *0.08);	
		}
		if current_hour = 14{
			nb_people <- int(people_in_station * 0.08);
			nb_tourist <- int(init_nb_tourist *0.07);	
		}
		if current_hour = 15{
			nb_people <- int(people_in_station * 0.06);
			nb_tourist <- int(init_nb_tourist *0.05);	
		}
		if current_hour = 16{
			nb_people <- int(people_in_station * 0.08);
			nb_tourist <- int(init_nb_tourist *0.04);	
		}
		if current_hour = 17{
			nb_people <- int(people_in_station * 0.1);
			nb_tourist <- int(init_nb_tourist *0.02);	
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
		create buildings from:shapefile_buildingds with:[height:int(read("Height"))];	
		create cruise_terminal from: shapefile_cruise_terminals with:[id:int(read("id"))];
		create hbf from: shapefile_hbf;
		create metro from: shapefile_public_transportation with: [station:string(read("station")), number:int(read("id"))];
		create roads from: clean_network(shapefile_roads.contents, 1.0, true, true);
		create crew_spot from:crew_spots;
		create sprinter_spot from: sprinter_spots;
		the_graph <- as_edge_graph(roads);
		create shuttle_spot from: shapefile_shuttle;
		create entry_points from: shapefile_entry_points with: [platform_nb::int(read("platform"))]; //number of platform taken from shapefile
		create walking_area from: shapefile_walking_paths {
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
		create traffic_road from:road_traffic;
		network_traffic <- as_edge_graph(traffic_road) with_optimizer_type "FloydWarshall";	
		create terminal_flow from:path_to_terminals;
		terminal_flows <- as_edge_graph(terminal_flow) with_optimizer_type "FloydWarshall";	
		
		create traffic_origin from:road_traffic_origin;
		create traffic_destination from:road_traffic_destination;
		create metro_origins from:metro_origin;
		create taxi from:shapefile_taxi_stand;
		create taxi_spot from:shapefile_taxi_stand;
		create point_HBF from:shapefile_reference_hbf;

	}
}

species ref_shuttle  skills: [moving]{
	point final_target;
	cruise_terminal current_terminal;
	int offset <- rnd(50);
	reflex go{
		list<cruise_terminal> active_terminal <- cruise_terminal where (each.state = 'active');
		final_target <- point(one_of(active_terminal));
		do goto target: final_target on: terminal_flows speed:50#km/#h;
	}
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}
		aspect default {
		draw circle(10) at:{location.x+offset,location.y+offset} color:rgb(122,193,198);
		draw circle(50) empty:true width:0.5 at:{location.x+offset,location.y+offset} color:rgb(122,193,198);
	}
}
species ref_taxi skills: [moving]{
	point final_target;
	cruise_terminal current_terminal;
	int offset <- rnd(50);
	reflex go{
		list<cruise_terminal> active_terminal <- cruise_terminal where (each.state = 'active');
		final_target <- point(one_of(active_terminal));
		do goto target: final_target on: terminal_flows speed:50#km/#h;
	}
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}
		aspect default {
		draw circle(15) at:{location.x+offset,location.y+offset} color:rgb(62,120,119);
	}
}
species ref_sprinter skills: [moving]{
	point final_target;
	cruise_terminal current_terminal;
	int offset <- rnd(50);
	reflex go{
		list<cruise_terminal> active_terminal <- cruise_terminal where (each.state = 'active');
		final_target <- point(one_of(active_terminal));
		do goto target: final_target on: terminal_flows speed:50#km/#h;
	}
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}
		aspect default {
		draw circle(20) at:{location.x+offset,location.y+offset} color:rgb(179,186,196);
	}
}
species point_HBF control:fsm{
	action create_re_sprinter{
		create ref_sprinter number:rnd(1) with:[location::location];
	}
	action create_re_shuttle{
		create ref_shuttle number:rnd(1) with:[location::location];
	}
	action create_re_taxi{
		create ref_taxi number:rnd(1) with:[location::location];
	}
}

species ref_taxi_return skills: [moving]{
	point final_target <- point(one_of(point_HBF));
	int offset <- rnd(50);
	reflex go{
		do goto target: final_target on: terminal_flows speed:50#km/#h;
	}
	reflex end when: (location distance_to final_target) <= 10{
		ask one_of(taxi){
			do create_people;
		}
		do die;
	}
	aspect default {
		draw circle(15) at:{location.x+offset,location.y+offset} color:rgb(62,120,119);
	}
}
species ref_shuttle_return skills: [moving]{
	point final_target <- point(one_of(point_HBF));
	int offset <- rnd(50);
	reflex go{
		do goto target: final_target on: terminal_flows speed:50#km/#h;
	}
	reflex end when: (location distance_to final_target) <= 10{
		ask one_of(shuttle){
			do create_people;
		}
		do die;
	}
	aspect default {
		draw circle(10) at:{location.x+offset,location.y+offset} color:rgb(122,193,198);
		draw circle(50) empty:true width:0.5 at:{location.x+offset,location.y+offset} color:rgb(122,193,198);
	}
}
species ref_sprinter_return skills: [moving]{
	point final_target <- point(one_of(point_HBF));
	int offset <- rnd(50);
	reflex go{
		do goto target: final_target on: terminal_flows speed:50#km/#h;
	}
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}
	aspect default {
		draw circle(20) at:{location.x+offset,location.y+offset} color:rgb(179,186,196);
	}
}

species cruise_terminal control:fsm{
	int id;
	int active_terminal <- 1;
	int size;
	int freq_curve;
	
	reflex frequency_curve{
		if current_hour < 8{
			freq_curve<-45;
		}
		if current_hour = 8 {
			freq_curve<-30;
		}
		if current_hour = 9{
			freq_curve<-25;
		}
		if current_hour = 10{
			freq_curve<-20;
		}
		if current_hour = 11{
			freq_curve<-30;
		}
		if current_hour>11{
			freq_curve<-3600;
		}
	}
	
	reflex disembarking_shuttle when: every(freq_curve#mn) {
		if self.state ="active" and init_nb_tourist>people_left_terminal{
			create ref_shuttle_return number:1 with:[location::location];	
		}
	}
	reflex disembarking_taxi when: every(freq_curve+rnd(3)#mn) {
		if self.state ="active" and init_nb_tourist>people_left_terminal{
			create ref_taxi_return number:1 with:[location::location];	
		}
	}
	reflex disembarking_sprinter when: every(freq_curve+rnd(10)#mn) {
		if self.state ="active" and init_nb_tourist>people_left_terminal{
			create ref_sprinter_return number:1 with:[location::location];	
		}
	}
	
	reflex active_terminals when: every(3600*24 #cycle){
		active_terminal <- active_terminal+1;
		if active_terminal > 3{
			active_terminal <- 1;
		}
	}
	
	state inactive initial:true {
		enter{
			size <-25;
			people_in_terminal<-0;
			people_left_terminal<-0;
		}
		transition to: active when: active_terminal = id;
	}
	state active{
		enter{
			size <-75;
		}
		transition to: inactive when: active_terminal !=id;
	}
	aspect base {
		draw circle(size) color:rgb(179,186,196);
		if self.state="active"{
			draw circle(size+people_in_terminal-people_left_terminal) empty:true width:0.5 color:rgb(179,186,196);
		}
	}
		
	aspect glow {
		draw circle(size*3) color: #white;
	}
}

species pedestrian_path {
	aspect default {
		draw shape color: #black;
	}
}

species buildings{
	int height;
	aspect default {
		draw shape color: rgb(120,125,130) depth:(height*4);
	}
}

species obstacle {
	geometry free_space;
}

species car skills: [moving]{
	point final_target <- point(one_of(traffic_destination));
	point origin <- location;
	int x;
	int y;
	
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}

	reflex move {
		do goto target: final_target on: network_traffic speed:15#km/#h;
	}	
	reflex show when: location distance_to origin > 5{
	x<-8;
	y<-4;
	}
	
	reflex kill when: every(10 #cycle){
		if location = origin{
			do die;
		}
	}
	
	aspect default {
		draw rectangle(x,y) color: #grey rotate:heading;
	}
}

species taxi_spot{}
species taxi skills:[moving] control:fsm {
	int luggage_capacity <- 3;
	int tourist_capacity <- 2;
	float speed <- 15 #km/#h;
	point target_loc <- point(one_of(crew_spot));
	taxi_spot own_spot;
	int people_create <- rnd(3);
	
	action create_people {
		people_left_terminal <- people_left_terminal+people_create;
		create people number:people_create with:[location::location]{
				size<-1.5;
				color<- #white;
				glow<-8;
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl);
		}	
	}
	action depart {
		do goto target: target_loc on: network_traffic speed:speed;
		if location distance_to point(one_of(shuttle_spot)) < 5{
			ask point_HBF {
				do create_re_taxi;	
			}
		}
	}
	
	state empty {
		enter {
			luggage_capacity <- 3;
			tourist_capacity <- 2;
			target_loc <- point(own_spot);
		}
		do depart;
		transition to: loading when: (location distance_to target_loc) <1;
	}
	
	state loading initial:true {
		enter{
			own_spot <- taxi_spot closest_to self;
		}
		transition to: full when: tourist_capacity < 1 or luggage_capacity < 1;
	}
	
	state full {
		enter {
			target_loc <- point(one_of(shuttle_spot));
		}
		do depart;
		transition to: empty when: (location distance_to target_loc <5);
	}

	aspect base {
		draw rectangle(4,4) color:rgb(46,83,97);
	}
}

species metro_train skills: [moving]{
	point final_target <- point(one_of(metro_origins));
	point origin <- location;
	
	reflex end when: (location distance_to final_target) <= 10{
		do die;
	}

	reflex move {
		do goto target: final_target on: network_metro speed:15#km/#h;
	}	
	
	reflex kill when: every(10 #cycle){
		if location = origin{
			do die;
		}
	}
	
	aspect default {
		draw rectangle(80,10) color:rgb(58,69,78) rotate:heading;
	}
}

species traffic_origin{
	reflex create_cars when: every(20#cycle){
		create car number: rnd(1) with: [location::location];
	}
}

species metro_origins{
	reflex metro_trains when: every(100#cycle){
		create metro_train number: 1 with: [location::location];
	}
}

species traffic_destination{}
species traffic_road{} 
species terminal_flow{}

species roads{}
species metro_line{
	rgb colors;
	aspect default {
		draw shape color:rgb(54,64,92) width:0.5;
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
		draw shape border:rgb(75,77,79) width:0.5 empty:true;
	}
}

species metro{
	image_file icon <- ubahn_icon;
	string station;
	int number;
			
	reflex create_opeople when: every(5+rnd(5) #mn){
		create people number: nb_people*0.1 with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(one_of(metro));
				size<-1.0;
				color<- rgb(179,186,196);
			}
		create people number: nb_people*0.01 with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
				final_target <- point(any_location_in(geometry(walking_area)));
				size<-1.0;
				color<- rgb(179,186,196);
			}	
		} 
		
	aspect base {
		draw icon size:8 rotate:180;
		draw station font:font("Calibri",5, #plain) color:#gray anchor:#center;
	}
}

species shuttle_spot control:fsm {
	crew current_crew;
	rgb color <- #blue;	

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
		draw circle(8) color:rgb(179,186,196);
		}
}

species shuttle skills:[moving] control:fsm {
	rgb color <- #blue;	
	image_file icon <- shuttle_icon;
	int luggage_capacity <- 100;
	int tourist_capacity <- 50;
	float speed <- 10 #km/#h;
	point target_loc <- point(one_of(crew_spot));
	bool is_scheduled;
	shuttle_spot own_spot;
	int people_create <- rnd(50);
	
	action create_people {
		people_left_terminal <- people_left_terminal+people_create;
		create people number:people_create with:[location::location]{
				size<-1.5;
				color<- #white;
				glow<-8;
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl);
		}	
	}
	
	action depart {
		do goto target: target_loc on:the_graph speed:speed;
		if location distance_to point(one_of(crew_spot)) < 10{
			ask point_HBF {
				do create_re_shuttle;	
			}
		}
	}
	
	reflex scheduled_depart when: every(1/shuttle_freq#h) {
		is_scheduled <- true;
	}
	
	state empty {
		enter {
			is_scheduled <- false;
			luggage_capacity <- 100;
			tourist_capacity <- 50;
			target_loc <- point(own_spot);
		}
		do depart;
		transition to: loading when: (location distance_to target_loc) <1;
	}
	
	state loading initial:true {
		enter{
			own_spot <- shuttle_spot closest_to self;
		}
		transition to: full when: tourist_capacity < 1 or luggage_capacity < 1 or is_scheduled;
	}
	
	state full {
		enter {
			target_loc <- point(one_of(sprinter_spot));
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
				size<-1.0;
				color<- rgb(179,186,196);
			}
			create tourist number: ((nb_tourist/train_freq)*(terminal_arrival_choice/100)) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			}	
			create tourist_shuttle number: ((nb_tourist/train_freq*2)*(1-terminal_arrival_choice/100)) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			}
			create tourist_taxi number: ((nb_tourist/train_freq*2)*(1-terminal_arrival_choice/100)) with: [location::location]{
				speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;	
			}
		}
	}	
	
	aspect base {
		draw square(2);
	}
}

species walking_area{}

species people skills: [moving] {
	point final_target;
	float size; 
	float speed <-gauss(3,2) #km/#h min: 1.0;
	int offsetx <- rnd(10);
	int offsety <- rnd(10);
	rgb color;
	int glow;
	
	reflex target{
		if final_target = nil{
			final_target <- any_location_in(geometry(network));
		}
	}
	reflex end when: (location distance_to final_target) <= 15{
		do die;
	}
	reflex move {
		do goto target: final_target on: network speed:speed;
	}	
	
	aspect default {
		draw circle(size) at:{location.x+offsetx,location.y+offsety} color:color;
	}
	aspect glow{
		draw circle(glow) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

species sprinter skills:[moving] control:fsm {
	point target_loc;
	int luggage_capacity;
	image_file icon <- sprinter_icon;
	float speed <- 10 #km/#h;
 
	action depart {
		do goto target: target_loc on:the_graph speed:speed;
		if location distance_to point(one_of(shuttle_spot)) < 5{
			ask point_HBF {
				do create_re_sprinter;	
			}
		}
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
			target_loc <- point(one_of(shuttle_spot));
		}
		do depart;
		transition to: empty when: (location distance_to target_loc <5);
	}
	
	aspect default {
		draw circle(6) color: rgb(72,123,143);
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
	int offsetx <- rnd(5);
	int offsety <- rnd(5);
	
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
			people_in_terminal <-people_in_terminal+1;
			do die;
		}
	}
	
	aspect default {
		draw circle(1.5) at:{location.x+offsetx,location.y+offsety} color: #white;
	}
	aspect glow{
		draw circle(8) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
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
	int offsetx <- rnd(7);
	int offsety <- rnd(7);
	
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
			people_in_terminal <-people_in_terminal+1;
			do die;
		}
	}
	
	aspect default {
		draw circle(1.5) at:{location.x+offsetx,location.y+offsety} color: #white;
	}
	aspect glow{
		draw circle(8) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}

species tourist_taxi skills:[moving] control:fsm {
	float speed <-gauss(3,1) #km/#h min: 1.0;
	bool dropped_luggage;
	int luggage_count <- 2;
	bool dropping_now <- false;
	float waiting_time;
	int tourist_line;
	image_file icon <- tourist_icon;
	taxi_spot the_spot;
	list<taxi_spot> known_boarding_areas;
	point final_target;
	bool knows_where_to_go <- false;
	taxi current_taxi;
	int offsetx <- rnd(5);
	int offsety <- rnd(5);
	
	state search_drop_off_luggage initial: true{
		if (final_target = nil) {
			final_target <- any_location_in(free_space);
		}
		do goto target: final_target on: network speed:speed;
		if (self distance_to final_target < 5.0) {
			final_target <- nil;
		}
		known_boarding_areas <- known_boarding_areas + (taxi_spot at_distance (perception_distance*2));
		transition to: goto_drop_off_luggage when: not empty(known_boarding_areas);
	}
	
	state goto_drop_off_luggage {
		enter {
			the_spot <- one_of(known_boarding_areas); 
			final_target <- the_spot.location;
			knows_where_to_go <- true;
		}
		do goto target: final_target on: network speed:speed;
		transition to: board_taxi when: (self distance_to final_target) < 2.0;
	}
	
	state board_taxi  {
		if (location distance_to final_target) < 2.0  {
			current_taxi <- taxi closest_to self;	
			current_taxi.tourist_capacity <- current_taxi.tourist_capacity - 1;
			people_in_terminal <-people_in_terminal+1;
			do die;
		}
	}
	
	aspect default {
		draw circle(1.5) at:{location.x+offsetx,location.y+offsety} color: #white;
	}
	aspect glow{
		draw circle(8) at:{location.x+offsetx,location.y+offsety} color: rgb(179,186,196);
	}
}


experiment "PCM_Simulation" type: gui {
	float minimum_cycle_duration <- 0.02;
	font regular <- font("Calibri", 12, # bold);
	parameter "Number of passengers" var: cruise_size init:2000 min:1 max:4500 category:"Amount of people";
	parameter "People in the station" var: people_in_station init:1000 min:1 max: 2000 category: "Amount of people";
	parameter "Frequency of trains (Fractions of an hour)" var: train_freq init:4.0 min:0.1 max:12.0 category: "Amount of people";
	parameter "Frequency of bus shuttles (Fractions of an hour)" var:shuttle_freq init:2.0 min:0.1 max:12.0 category: "Infrastructure and service";
	parameter "Size of welcome center" var: nb_sprinters init:3 min:1 max: 5 category: "Infrastructure and service";
	parameter "Perception of info" var: perception_distance init:250.0 min:1.0 max:10000.0 category: "Infrastructure and service";
	parameter "% of tourists using welcome center" init:80.0 var:terminal_arrival_choice min:1.0 max:100.0 category:"Behavioral profile";
	parameter "% of tourists arriving in HH by train" init:20.0 var:hamburg_arrival_choice min:1.0 max:100.0 category: "Behavioral profile";

	output {
		display charts  background: rgb(55,62,70) refresh:every(5#mn){
			chart "Tourist in Central Station" type: pie size:{1,0.3} position: {0,0}background: rgb(55,62,70) axes: #white color: rgb(122,193,198) legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Disoriented tourists" value: nb_tourists_disoriented color: rgb(122,193,198);
				data "Tourists going to the luggage drop off area" value: nb_tourists_to_drop_off color: rgb(120,125,130);
				data "Tourists dropping off their luggage" value: nb_tourists_dropping_luggage color: rgb(179,186,196);
				data "Tourists going to the shuttles" value: nb_tourists_to_shuttles color: rgb(200,200,200);
			}
			chart " " type: series size:{1,0.3} position: {0,0.3} background: rgb(55,62,70) axes: #white color: #white legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Disoriented tourists" value: nb_tourists_disoriented color: rgb(179,186,196) marker_size:0 thickness:2;
				data "Tourists going to the luggage drop off area" value: nb_tourists_to_drop_off color: rgb(120,125,130) marker_size:0 thickness:2;
				data "Tourists in the area" value: nb_tourists color: rgb(122,193,198) marker_size:0 thickness:2;
			}
			chart " " type: series size:{1,0.3} position: {0,0.6} background: rgb(55,62,70) axes: #white color: #white legend_font:("Calibri") label_font:("Calibri") tick_font:("Calibri") title_font:("Calibri"){
				data "Tourists dropping off their luggage" value: nb_tourists_dropping_luggage color: rgb(179,186,196) marker_size:0 thickness:2;
				data "Tourists going to the shuttles" value: nb_tourists_to_shuttles color: rgb(122,193,198) marker_size:0 thickness:2;
			}
		}
		display map type:opengl  background: rgb(30,40,49)
		{
			image site_plan transparency:0.75;
			image intervention_plan position:{500,300};	
			
			//species buildings aspect:default transparency:0.9;
			species metro_line aspect:default refresh:false;
			species hbf aspect:base refresh:false;
			species metro aspect: base refresh:false;
			species shuttle_spot aspect: base ;
			species people aspect: default;
			species people aspect: glow transparency:0.85;
			species tourist aspect: default;
			species tourist_taxi aspect: default;
			species tourist_shuttle aspect: default;
			species tourist aspect: glow transparency:0.85;
			species tourist_shuttle aspect: glow transparency:0.85;
			species tourist_taxi aspect: glow transparency:0.85;
			species sprinter aspect: default;
			species crew aspect: default;
			species crew_spot aspect:base ;
			species shuttle aspect: base;
			species cruise_terminal aspect:base;
			species cruise_terminal aspect: glow transparency:0.85;
			species car aspect:default;
			species taxi aspect:base;
			species metro_train aspect:default;
			species ref_shuttle aspect:default;
			species ref_taxi aspect:default;
			species ref_sprinter aspect:default;
			species ref_shuttle_return aspect:default;
			species ref_taxi_return aspect:default;
			species ref_sprinter_return aspect:default;
			
			overlay position: { 5, 5 } size: { 240 #px, 680 #px } background:rgb(55,62,70) transparency: 1.0 border: #black  {
                rgb text_color<-rgb(179,186,196);
                float y <- 12#px;
  				draw "Agents in the simulation" at: { 10#px, y } color: rgb(122,193,198) font: font("Calibri", 14, #plain) perspective:true;
                y <- y + 10 #px;
                draw circle(8#px) at: { 13#px, y +4#px } color: rgb(120,125,130);
                draw circle(2#px) at: { 13#px, y +4#px } color: #white;
                draw "CRUISE TOURIST" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
				y <- y + 14 #px;
                draw circle(2#px) at: { 13#px, y +4#px } color: rgb(179,186,196);
                draw "PEOPLE" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
                y <- y + 14#px;
                draw circle(3#px) at: { 13#px, y +4#px } color: rgb(72,123,143);
                draw "LUGGAGE SPRINTER" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
                y <- y + 14#px;
                draw circle(6) at: { 13#px, y +4#px } color:rgb(179,186,196);
                draw "BUS SHUTTLE [INTERACTION]" at: { 25#px, y + 8#px } color: text_color font: font("Calibri", 9, #bold) perspective:true;
                y <- y + 14 #px;
                draw "_____________________________"at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 15, #bold) perspective:true;
                y <- y + 21 #px;
				draw "Waiting time at welcome center" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(avg_waiting_time/15, 8#px) at: { 0#px, y +4#px } color:rgb(179,186,196);
                y <- y + 14 #px;
                draw "Drop-off line length" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_dropping_luggage*10, 8#px) at: { 0#px, y +4#px } color:rgb(122,193,198);
                y <- y + 14 #px;
                draw "Expected people arriving to welcome center" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_to_drop_off*10, 8#px) at: { 0#px, y +4#px } color:rgb(120,125,130);
                y <- y + 14 #px;
                draw "Disoriented" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_disoriented*10, 8#px) at: { 0#px, y +4#px } color:rgb(62,120,119);
                y <- y + 14 #px;
                draw "On the way to bus shuttle" at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 14 #px;
                draw rectangle(nb_tourists_to_shuttles*10, 8#px) at: { 0#px, y +4#px } color:rgb(46,83,97);
                y <- y + 14 #px;
                draw "_____________________________"at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 15, #bold) perspective:true;
                y <- y + 21 #px; 
                draw time_info at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
                y <- y + 21 #px; 
                draw "Perople to the terminal: "+ string(people_in_terminal) at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
           		 y <- y + 21 #px; 
                draw "Perople from the terminal: "+ string(people_left_terminal) at: { 25#px, y + 8#px } color:rgb(120,125,130) font: font("Calibri", 12, #plain) perspective:true;
           
            }
			
////////////////////User interaction starts here		
			event mouse_move action: move;
			event mouse_up action: click;
			event 'r' action: kill;
			event 'c' action: duplicate;
			graphics "Full target" {
				int size <- length(moved_agents);
				if (size > 0){
					rgb c1 <- rgb(62,120,119);
					rgb c2 <- rgb(62,120,119);
					draw zone at: target empty: false border: false color: (can_drop ? c1 : c2);
					draw string(size) at: target + { -15, -15 } font: font("Calibri", 8, #plain) color: rgb(179,186,196);
					draw "'r': remove" at: target + { -15, 0 } font: font("Calibri", 8, #plain) color: rgb(179,186,196);
					draw "'c': copy" at: target + { -15, 15 } font: font("Calibri", 8, #plain) color: rgb(179,186,196);
				}
			}
////////////////////User interaction ends here	
		}
	}
}
