/***
* Name: Interactive_Move_Terminals_Test_1
* Author: JLopez
* Description: Given tourists (cruise passengers) and people in the city (people), the model test how paths of the people change based on real time interaction with the user by modifying (moving,copyng, removing) the destinations.
* Tags: Tag1, Tag2, TagN
***/
/* Insert your model definition here */
model PCM_Simulation

global {

	list<terminal> moved_agents ;
	point target;
	geometry zone <- circle(50);
	bool can_drop;
	
	string cityGISFolder <- "./../external/";
	file shape_file_buildings <- file(cityGISFolder + "buildings.shp");
	file shape_file_roads <- file(cityGISFolder + "road.shp");
	file shape_file_bounds <- file(cityGISFolder + "bounds.shp");
	file shape_file_rails <- file(cityGISFolder + "BahnlinienDISK_HH.shp");
	file shape_file_transport_hubs <- file(cityGISFolder + "HaltepunkteBahnlinie.shp");
	file shape_file_terminals <- file(cityGISFolder + "Destinations.shp");
	file shape_hbf <- file(cityGISFolder + "Hbf.shp");
	geometry shape <- envelope(shape_file_roads);
	float step <- 2 #mn;
	int nb_people <- 20;
	int nb_tourists <- 200;
	int nb_trains <- 10;
	int nb_taxis <- 20;
	int current_hour update: (time / #hour) mod 24;
	int min_work_start <- 0;
	int max_work_start <- 12;
	int min_work_end <- 12; 
	int max_work_end <- 23; 
	
	int nb_people_arriving;
	int nb_people_departing;
	
	float min_speed_ppl <- 0.05 #km / #h;
	float max_speed_ppl <- 0.2 #km / #h;
	float min_speed_transport <- 0.5 #km / #h;
	float max_speed_transport <- 1 #km / #h;  
	graph the_graph;
	graph the_rails;
	geometry free_space;
	int maximal_turn <- 360; //in degree
	int cohesion_factor <- 5;
	float people_size <- 5.0;
		
	action kill {
		ask moved_agents{
			do die;
		}
		moved_agents <- list<terminal>([]);
	}

	action duplicate {
		geometry available_space <- (zone at_location target) - (union(moved_agents) + 10);
		create terminal number: length(moved_agents) with: (location: any_location_in(available_space));
	}

	action click {
		if (empty(moved_agents)){
			list<terminal> selected_agents <- terminal inside (zone at_location #user_location);
			moved_agents <- selected_agents;
			ask selected_agents{
				difference <- #user_location - location;
				color <- # olive;
			}
		} else if (can_drop){
			ask moved_agents{
				color <- # red;
			}
			moved_agents <- list<terminal>([]);
		}
	}

	action move {
		can_drop <- true;
		target <- #user_location;
		list<terminal> other_agents <- (terminal inside (zone at_location #user_location)) - moved_agents;
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
	
	init {
		
		free_space <- copy(shape);
		//Creation of the buildinds
		create building from: shape_file_buildings {
			//Creation of the free space by removing the shape of the different buildings existing
			free_space <- free_space - (shape + people_size);
		}
		//Simplification of the free_space to remove sharp edges
		free_space <- free_space simplification(1.0);
		//Creation of the people agents
		create terminal from: shape_file_terminals;
		create road from: shape_file_roads ;
		the_graph <- as_edge_graph(road);
		create transport_hub from: shape_file_transport_hubs;
		create rail from: shape_file_rails;
		the_rails <- as_edge_graph(rail);
		create hbf from: shape_hbf;
		
		create people number: nb_people {
			speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			target_loc <- any_location_in (free_space);
			location <- any_location_in (free_space);
		}	
		create tourist number: nb_tourists {
			speed <- min_speed_ppl + (max_speed_ppl - min_speed_ppl) ;
			start_work <- min_work_start + rnd (10) ;
			end_work <- min_work_end + rnd (10) ;
			living_place <- one_of(hbf) ;
			objective <- "resting";
			location <- any_location_in(one_of(hbf));
		}	
		create train number: nb_trains {
			speed <- min_speed_transport + (max_speed_transport - min_speed_transport) ;
			start_work <- min_work_start + rnd (max_work_start - min_work_start) ;
			end_work <- min_work_end + rnd (max_work_end - min_work_end) ;
			living_place <- one_of(transport_hub) ;
			working_place <- one_of(transport_hub) ;
			objective <- "resting";
			location <- any_location_in(one_of(transport_hub));	
		}
		create taxi number: nb_taxis {
			speed <- min_speed_transport + (max_speed_transport - min_speed_transport) ;
			start_work <- min_work_start + rnd (max_work_start - min_work_start) ;
			end_work <- min_work_end + rnd (max_work_end - min_work_end) ;
			living_place <- one_of(hbf) ;
			objective <- "resting";
			location <- any_location_in(one_of(hbf)) ;	
		}
	}
}

species building {
	float height <- 6.0 + rnd(50);
	rgb color <- #gray  ;	
	aspect base {
		draw shape color: color depth: height ;
	}
}

species road  {
	rgb color <- #black ;
	aspect base {
		draw shape color: color ;
	}
}

species terminal skills: [moving] {
	rgb color <- #red ;
	geometry shape <- square(20);
	point difference <- { 0, 0 };
	reflex r {
		if (!(moved_agents contains self)){}
	}
	aspect default{
		draw shape color: color at: location;
	}
}

species transport_hub  {
	rgb color <- #blue ;
	aspect base {
		draw square(20) color: color ;
	}
}

species hbf  {
	rgb color <- #black ;
	aspect base {
		draw square(20) color: color ;
	}
}

species rail  {
	rgb color <- #gray ;
	aspect base {
		draw shape color: color ;
	}
}


species people skills:[moving] {
	point target_loc;
	float speed <- 5 + rnd(1000) / 1000;
	point velocity <- {0,0};
	float heading max: heading + maximal_turn min: heading - maximal_turn;
	float size <- people_size; 
	rgb color <- #black;
		
	//Reflex to kill the agent when it has evacuated the area
	reflex end when: location distance_to target_loc <= 100 * people_size{
		target_loc<-any_location_in(free_space);
	}
	//Reflex to compute the velocity of the agent considering the cohesion factor
	reflex follow_goal  {
		velocity <- velocity + ((target_loc - location) / cohesion_factor);
	}
	//Reflex to apply separation when people are too close from each other
	reflex separation {
		point acc <- {0,0};
		ask (people at_distance size)  {
			acc <- acc - (location - myself.location);
		}  
		velocity <- velocity + acc;
	}
	//Reflex to avoid the different obstacles
	reflex avoid { 
		point acc <- {0,0};
		list<building> nearby_obstacles <- (building at_distance people_size);
		loop obs over: nearby_obstacles {
			acc <- acc - (obs.location - location); 
		}
		velocity <- velocity + acc; 
	}
	//Reflex to move the agent considering its location, target and velocity
	reflex move {
		point old_location <- copy(location);
		do goto target: location + velocity ;
		if not(self overlaps free_space ) {
			location <- ((location closest_points_with free_space)[1]);
		}
		velocity <- location - old_location;
	}	
	aspect default {
		draw pyramid(size) color: color;
		draw sphere(size/3) at: {location.x,location.y,size} color: color;
	}
}

species tourist skills:[moving] {
	rgb color <- #green ;
	hbf living_place <- nil ;
	int start_work ;
	int end_work  ;
	string objective ; 
	point the_target <- nil ;
		
	reflex time_to_work when: current_hour = start_work and objective = "resting"{
		objective <- "working" ;
		nb_people_arriving <- tourist count(each.objective = "working");
		the_target <- point(one_of(terminal));
	}
		
	reflex time_to_go_home when: current_hour = end_work and objective = "working"{
		objective <- "resting" ;
		nb_people_departing <- tourist count(each.objective = "resting");
		the_target <- any_location_in (living_place); 
	} 
	 
	reflex move when: the_target != nil {
		do goto target: the_target on: the_graph ; 
		if the_target = location {
			the_target <- nil ;
		}
	}
	
	aspect base {
		draw sphere(3) color: color;
	}
}

species train skills:[moving] {
	rgb color <- #black ;
	transport_hub living_place <- nil ;
	transport_hub working_place <- nil ;
	int start_work ;
	int end_work  ;
	string objective ; 
	point the_target <- nil ;
		
	reflex time_to_work when: current_hour = start_work and objective = "resting"{
		objective <- "working" ;
		the_target <- any_location_in (working_place);
	}
		
	reflex time_to_go_home when: current_hour = end_work and objective = "working"{
		objective <- "resting" ;
		the_target <- any_location_in (living_place); 
	} 
	 
	reflex move when: the_target != nil {
		do goto target: the_target on: the_rails ; 
		if the_target = location {
			the_target <- nil ;
		}
	}
	
	aspect base {
		draw circle(5) color: color;
	}
}
species taxi skills:[moving] {
	rgb color <- #orange ;
	hbf living_place <- nil ;
	int start_work ;
	int end_work  ;
	string objective ; 
	point the_target <- nil ;
		
	reflex time_to_work when: current_hour = start_work and objective = "resting"{
		objective <- "working" ;
		the_target <- point(one_of(terminal));
	}
		
	reflex time_to_go_home when: current_hour = end_work and objective = "working"{
		objective <- "resting" ;
		the_target <- any_location_in (living_place); 
	} 
	 
	reflex move when: the_target != nil {
		do goto target: the_target on: the_graph ; 
		if the_target = location {
			the_target <- nil ;
		}
	}
	
	aspect base {
		draw circle(5) color: color;
	}
}

experiment "PCM_Simulation" type: gui {
	font regular <- font("Helvetica", 14, # bold);
	output {
		display graph refresh:every(10#mn){
			chart "tourist in the city" type: series size:{1,0.5} position: {0,0} {
				data "number of people departing" value: nb_people_departing color: #red;
				data "number of people arriving" value: nb_people_arriving color: #green;
			}
		}
		display map type:java2D 
		{
			graphics "Empty target" {
				if (empty(moved_agents)){
					draw zone at: target empty: false border: false color: #wheat;
				}
			}
			species terminal;
			species building aspect: base ;
			species transport_hub aspect: base ;
			species rail aspect: base ;
			species people ;
			species tourist aspect: base ;
			species train aspect: base ;
			species taxi aspect: base;
			species hbf aspect: base;
			
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
		}
	}
}
