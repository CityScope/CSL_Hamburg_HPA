/***

* Name: Multi-Level-Ready
* Author: JLopez
* Description: Large-scale model. It aims to consider all agents involved in the entire process. Currently not working.
* Tags: Tag1, Tag2, TagN


General idea of the model to build:

	-The overall idea is to create a model to represent the embark and disembarkation of cruise vessels in the city of Hamburg.
	-The project is focused in the path followed by people since their arrival in the city at the Main Station (HBF) to their departure in the vessels from the Cruise Terminals (and vice-versa).
	-Several transportation means are considered: Car, Taxi, Bus shuttle and Luggage sprinters.
	-The main spaces where the actions are performed are defined by shapefiles: Main Station (HBF), Luggage and Taxi drop-off area at the main station, Bus station (ZOB), Cruise Terminals, and the Parking lots of every cruise terminal. Also buildings are imported to define streets by the free_space between them.
	-Two types of people are considered in the model: Citizens of hamburg (just happen to be in the city) and ’people_sample’ (cruise passengers) either in Arrival or Departure mode.

The first test run of the model should mirror the following process:

	1. Trains arrive at the station (HBF) scheduled constantly throughout the day. The Cruise Terminals have vessels scheduled every 24 hours. Vessels have different sizes.
	2. people arriving at the station in those trains are Citizens of hamburg (who leave the station to a random destination) and ‘people_sample’ (cruise passengers) carrying pieces of luggage
	3. Cruise passengers arriving at the station go to the Drop-off area to: 3a - Take a taxi directly to the Cruise Terminal that has a vessel; 3b - Leave their luggage in a van (Sprinter) and proceed to the Bus station (ZOB) to take a bus shuttle to the Cruise Terminal that has a vessel.
	4. Some cruise passengers go directly from home with their own car. They park the car in the Parking lot next to the Cruise Terminal and they walk in.
	5. At the same time, the inverse process takes place for people arriving at the city in the vessels: They take taxis and bus shuttles to the train station, and cars home.


Some weak points:

-people taking a transportation: people take a bus
-Scheduled and cyclical actions: A bus departs every 15 minutes from 8 am to 6 pm; Every 30 minutes a train arrives at the station.
-Creation of species based on a condition: Every 30 minutes a train arrives at the station, 200 people arrive in the city.
-Scheduled creation of species: When a vessel is in the terminal, people start disembarkation gradually from 8 am to 10 am until the vessel is empty.
-Given an overall amount of species (people) by one variable (Vessel_capacity), divide people in behavioral groups by percentage of that variable (30% take the car, 70% take the bus).
-Chained tasks: First go to the Drop-off area and leave the luggage, then take the bus, then arrive at the Terminal.
-Geometric distribution of agents performing one same task: Several people waiting in a line, just the first one in the queue can perform the action (take the bus).
-Overall setting: Given a random number of families (species people), create one car (species Car) to be used by that family.
-Walking tendencies: Given an origin and a destination, walk the route with a higher amount of restaurants. 
-Walking tendencies: Cohesion factor.

***/

model PCM_test20181101

global {
	string cityGISFolder <- "./../external/";
	
	file shepefile_Buildings <- file(cityGISFolder + "buildings.shp"); 
	file shepefile_HBF <- file(cityGISFolder + "Hbf.shp"); 
	file shepefile_Cruise_Terminals <- file(cityGISFolder + "Cruise_terminals.shp");
	file shepefile_Parkings <- file(cityGISFolder + "Parkings.shp");
	file shepefile_ZOB <- file(cityGISFolder + "ZOB.shp");
	file shepefile_Dropoffarea_HBF <- file(cityGISFolder + "Dropoffarea.shp");
	file shepefile_Foursquare_venues <- file(cityGISFolder + "FS_venues.shp"); 

	geometry shape <- envelope (shapefile_Buildings); /*The boundaries of the experiment match the boundaries of the Buildings layer*/
	geometry free_space; /*Free space inbetween buildings*/

	float current_hour update: (time / #hour) mod 24; /*Definition of what time it is*/
	float step <- 5 #mn; /*Every step represents 5 minutes */

	/***Not sure about this part***/
	float walking_speeds {
		slow <- 2.5 #km/h;
		medium <- 5.0 #km/h;
		fast <- 7.5 #km/h;
	}

	float cohesion_factors {
		low <- 0.5;
		medium <- 1.0;
		high <- 1.5;
	}

	int vessel_sizes {
		small <- 800;
		medium <- 2500;
		large <- 5000;
	}

	text cruise_brands {
		msc <- "MSC";
		aida <- "Aida";
		ncl <- "Norwegian Cruise Lines";
	}

	/***Number of elements in the experiment***/
	int nb_people_hamb <- 100;
	int nb_Taxis <- 10;
	int nb_Car_hamb <- 10;
	int nb_Bus_shuttle <- 3;
	int nb_Sprinters <- 3;

	action board{
		/*people boarding the vessel*/
	}

	init {
		create Buildings from shapefile_Buildings with: [height::int(read("Height"))];
		create HBF from shapefile_HBF with: [height::int(read("Height"))];
		create Cruise_Terminals from shapefile_Cruise_Terminals with: [height::int(read("Height"))];
		create Parking from shapefile_Parkings;
		create ZOB from shapefile_ZOB;
		create Dropoffarea from shapefile_Dropoffarea_HBF;
		create Venues from shapefile_Frousquare_venues with: [weight::int(read("visitsCoun"))];

		/***Creation of the space between the buildings***/
		free_space <- copy(shape);
		free_space <- free_space - Buildings; /*Freepace created by removing the spape of the Buildings*/
		free_space <- free_space simplification(1.0); /*Simplification to remove sharp edges*/

		create people_hamb number:nb_people_hamb{ /*Generic people in the city*/
		} 
		...

		create people_arriving from: "#Ship Schedules.csv" with: [nb_people_arriving::read("Passenger")] header: true number:nb_people_arriving;

		create people_departing from: "#Ship Schedules.csv" with: [nb_people_departing::read("Passenger")] header: true number:nb_people_departing;/*Cruise Turists: sample of the experiment*/
		...

		create Taxi /*Taxis carrying people*/
		...

		create Car_hamb /*Generic car in the city*/
		...

		create Car_sample /*Car used by people_sample (Cruise Turists)*/
		...

		create Bus_Shuttle /*Bus shuttle carrying people*/
		...

		create Sprinter /*Van carrying luggage*/
		...
}

species  Buildings {
	int height <- height; /*****************the column 'Height' from Shapefile*/
	rgb color <- #gray;
	aspect base {
		draw shape depth: height color: color;
	}
}

species HBF {
	int height <- height; /*****************the column 'Height' from Shapefile*/
	rgb color <- #pink;
	string has_train <- 'False' /***************** Change True/False randomly every 30 minutes*/
	int incoming_people_hamb <-nil
	int incoming_people_sample <-nil /************* Percentage of 'people_departing' that take train, taken from external CSV file*/

	when current_hour < 7:
		incoming_people_hamb <- rnd(20) + nb_people_hamb * 100 / 2;
	when current_hour >= 7 and current_hour < 22:
		incoming_people_hamb <- rnd(50) + nb_people_hamb * 100 / 50;
	when current_hour >= 22:
		incoming_people_hamb <- rnd (20) + nb_people_hamb * 100 / 2;

	when current_hour < 7:
		incoming_people_sample <- 5%; /* % of incoming_people_sample*/
	when current_hour >= 7 and current_hour < 11: 
		incoming_people_sample <- 10%; /* % of incoming_people_sample*/
	when current_hour >= 11 and current_hour < 13:
		incoming_people_sample <- 40%; /* % of incoming_people_sample*/
	when current_hour >= 13 and current_hour < 15:
		incoming_people_sample <- 20%; /* % of incoming_people_sample*/
	when current_hour >= 15 and current_hour < 17:
		incoming_people_sample <- 10%; /* % of incoming_people_sample*/
	when current_hour >= 17: 
		incoming_people_sample <- 5%; /* % of incoming_people_sample*/

	aspect base {
		draw shape depth: height color: color;
	}
}

species Cruise_Terminals {
	int height <- height;
	rgb color <- #pink;
	
	For every element in list <Cruise_Terminals>: /***************** Write properly*/
		string has_vessel <- 'False' /***************** Change True/False from CSV file - Schedules*/
		when has_vessel = True {
			int vessel_size <- /**** Take from CSV file - schedules*/
			string cruise_brand <- /*** Take from CSV file - schedules*/
		}


	aspect base {
		draw shape depth: height color: color;
	}
}

species Parking {
	rgb color <- #gray;

	/*shape Terminal_associated_to <- column from shapefile Parkings*/

	aspect base {
		draw shape color: color;
	}
}

species ZOB {
	rgb color <- #gray;
	string has_shuttle <- 'True' /***************** When it has a Bus_shuttle inside the boundary*/

	aspect base {
		draw shape color: color;
	}
}

species Dropoffarea {}
	rgb color <- #gray;
	string has_taxi <- 'True' /***************** When it has a Taxi inside the boundary*/
	string has_sprinter <- 'True' /***************** When it has a Sprinter inside the boundary*/
	aspect base {
		draw shape color: color;
	}
}

species Venues {
	float weight <- weight; /*****************Add here the column 'Visits' from Shapefile*/
	rgb color <- ; /*****************Make color ramp correspong to weight*/
	aspect base {
		draw square(10) color:color;
	}
}

species people_hamb {
	rgb color <- #gray;
	point origin <- nil;
	point destination <- one_of (buildings);
	float speed <- one_of (walking_speeds);

	/*Cohesion Factor to define*/
	/*people_hambs arriving in HBF: To define. Some start in HBF when a train arrives, some start at home.*/
	/*On their route to destination, they tend to walk closer/choose paths near Shops with higher statistics of visits.*/
	/*When they arrive at destination: wait, change destination to a random new one.*/

		reflex move when: destination != nil {
			do goto target: destination on: free_space ;
			if destination = location {
				destination <- one_of (buildings) ;
				/*When they arrive at destination: Wait 1 hour and choose a new destination*/
			}
		}

	aspect base{
		draw sphere (5) color: color;
	}
}

species people_arriving {
	rgb color <- #red;
	point origin <- one_of(Cruise_Terminals) when Cruise_Terminals.has_vessel = True; /*people with the same Group_ID have the same origin*/
	point destination <- nil;
	int Group_ID <- nil; /*number of resrvations made in the cruise VS numbr of people on board. It defines how Groups, couples, families are organized*/
	int count unique(Group_ID) /*Amount of people with the same Group_ID in the dataset (count)*/

	/*People arriving schedules follow data on external CSV*/

	species people_arriving_car parent people_arriving number : vessel_size*100 / 30 {/*percentage of people taking car taken from CSV file for each brand*/ 
		point destination <- one_of(Parkings) when Parking.Terminal_associated_to = origin; /*people with the same Group_ID have the same Final_destination*/
		luggage_count <- rnd(4);
		path my_path;

		reflex move {
			my_path <- self goto (target:destination, speed:one_of(walking_speeds));
			if (target = location) {
				do enter_car when car_ID = people_ID;
				destination_2 <- one_of(buildings);
			}
		}
	}

	species people_arriving_bus_taxi parent people_arriving number: (count(people_arriving)-count(people_arriving_car)) {
		point destination <- HBF;
		luggage_count <- rnd(3)
		int people_taking_bus_with_luggage <- people_departing_bus_taxi *100 / 30/*Number taken from CSV FILE*/
		int people_taking_taxi_with_luggage <- people_departing_bus_taxi *100 / 30/*Number taken from CSV FILE*/
			
		reflex move {
			/*Walk from the ZOB or the Dropoffarea to the Train station*/
			/*Spend between 30 and 120 minutes visiting the city*/
		}

		reflex wait {
		 /********* Define how to wait in a queue*/
		}

		reflex take_taxi {
			origin <- location
			target <- /* FIRST TAXI IN THE LINE*/
			my_path <- self goto (target:target, speed:one_of(walking_speeds))
			if (target=location){
				do /*ENTER TAXI WITHOUT REACHING MAXIMUM TAXI CAPACITY*/
		}

		reflex take_bus {
			origin <- location
			my_path <- self goto (target:ZOB, speed:one_of(walking_speeds))
			if (target=location){
				if ZOB.has_shuttle = True{
						/*people ENTER SHUTTLE WITHOUT REACHING MAXIMUM CAPAITY*/
				else wait /*WAIT UNTIL HAS_SHUTTLE = TRUE*/
				}
			}
		}
	}

	aspect base{
		draw sphere (5) color: color;
	}
}

species people_departing {
	rgb color <- #green;
	species people_departing_car parent people_departing number : vessel_size*100 / 30 /*percentage of people taking car taken from CSV file for each brand*/ {
		point destination <- one_of(Cruise_Terminals) when Cruise_Terminals.has_vessel = True;
		point origin <- location
		luggage_count <- rnd(4);
		path my_path;

		reflex take_car{
				/*Get inside their cars*/
		}

		reflex move {
			my_path <- self goto (target:destination, speed:one_of(walking_speeds))
			if (target=location){
				do board
				 /* Walk from the Parking to the Terminal*/
			}
		}
	}

	species people_departing_bus_taxi parent people_arriving number : vessel_size-count(people_departing_car) {
		point origin <- HBF
		luggage_count <- rnd (3);
		point destination <- Dropoffarea;
		int people_taking_bus_with_luggage <- people_departing_bus_taxi *100 / 30/*Number taken from CSV FILE*/
		int people_taking_taxi_with_luggage <- people_departing_bus_taxi *100 / 30/*Number taken from CSV FILE*/
		int people_droping_off_luggage_and_taking_bus <- people_departing_bus_taxi *100 / 30/*Number taken from CSV FILE*/
			
		reflex move {
			/*Spend between 30 and 120 minutes visiting the city - random - make sure to board the cruise on time*/
			/*walk from the tran station to the dropoffarea, then to ZOB, then to the Terminal*/
			my_path <- self goto (target:destination, speed:one_of(walking_speeds))
			if (target=location){
				if luggage_count < 2{
					if Dropoffarea.has_taxi = True{ /*The amount of people taking taxi is taken from a CSV file*/
						do take_taxi
						else do take_bus
					}
				else do leave_luggage
				}
			}
		}

		reflex wait {
		 /********* Define how to wait in a queue*/
		}

		reflex take_taxi {
			origin <- location
			target <- /* FIRST TAXI IN THE LINE*/
			my_path <- self goto (target:target, speed:one_of(walking_speeds))
			if (target=location){
				do /*ENTER TAXI WITHOUT REACHING MAXIMUM TAXI CAPACITY*/
		}

		reflex leave_luggage {
			origin <- location
			my_path <- self goto (target:Dropoffarea, speed:one_of(walking_speeds))
			if (target=location){
				if Dropoffarea.has_sprinter = True{

						/*people DELIVER LUGGAGE ONE BY ONE
						IT TAKES 30 to 180 SECONDS TO LEAVE LUGGAGE*/

					Sprinter.luggage_capacity <- Sprinter.luggage_capacity - people_departing_bus_taxi.luggage_count
					people_departing_bus_taxi.luggage_count <- 0
				else wait /*WAIT UNTIL Dropoffarea.has_sprinter = True */
				}
			}

		reflex take_bus {
			origin <- location
			my_path <- self goto (target:ZOB, speed:one_of(walking_speeds))
			if (target=location){
				if ZOB.has_shuttle = True{
						/*people ENTER SHUTTLE WITHOUT REACHING MAXIMUM CAPAITY*/
				else wait /*WAIT UNTIL HAS_SHUTTLE = TRUE*/
				}
			}
		}
	}

	aspect base{
		draw sphere (5) color: color;
	}
}

species Taxi {
	rgb color <- #yellow;
	point origin <- nil;
	point destination <- nil;
	
/*
•	Can only carry groups of people_sample when the Group_ID of every person is the same
•	Carries people_sample-sample with people_sample ‘mode’ = Taxi ‘mode’
•	When carrying people_sample:
	•	Destination: ‘Final_destination’ from people_sample
	•	When arrives at destination: unload people_sample
•	When not carrying people_sample:
	•	Origin: current location
	•	Destination: Source
	•	When arrives at destination: load people_sample

•	Speed (random) 20 to 70 (reload every 5 min)

•	From Time 0-8:
	•	Percentage of taxis in Departure mode: 5%
	•	Percentage of taxis in Arrival mode: 95%
•	From Time 8-10:
	•	Percentage of taxis in Departure mode: 15%
	•	Percentage of taxis in Arrival mode: 85%
•	From Time 11-12:
	•	Percentage of taxis in Departure mode: 50%
	•	Percentage of taxis in Arrival mode: 50%
•	From Time 12-14:
	•	Percentage of taxis in Departure mode: 85%
	•	Percentage of taxis in Arrival mode: 15%
•	From Time 15-23:
	•	Percentage of taxis in Departure mode: 98%
	•	Percentage of taxis in Arrival mode: 2%
•	Mode: Departure
	•	Origin: HBF dropoff area
•	Mode: Arrival
	•	Origin (random): from Cruise Terminals when ‘Has_vessel = yes’
*/
	...
	species people_in_taxi parent: people_sample schedules: []

	reflex let_people_enter {
		list<people_sample> entering_people <- (people_sample inside self);
		if !(empty (entering_people)) {
			capture entering_people as: people_in_taxi returns: people_captured;
			}
		}
	}

	reflex let_people_leave {
		list<people_in_taxi> leaving_people <- (list (members))
		if !(empty (leaving_people)) {
			release leaving_people as: people_sample in: free_space;
		}
	}

	aspect base{
		draw cube (10) color: color;
	}

species car_hamb {
	rgb color <- #gray;
	point origin <- nil;
	point destination <- one_of(buildings);
	/*	float speed <- random (20 to 70)#km/h reload every 5 #mn;	*/

	/*When they arrive at destination: wait, change destination to a random new one.*/

		reflex move when: destination != nil {
			do goto target: destination on: free_space ;
			if destination = location {
				destination <- one_of(buildings) ;
				/*When they arrive at destination: Wait 1 hour and choose a new destination*/
			}
		}

	aspect base{
		draw cube (10) color: color;
	}
}

species car_sample {
	rgb color <- #gray;
	point origin <- nil;
	point destination <- nil;

/* 
•	Initial amount of car_sample = amount of unique ‘people_ID’ from people_departing_car + people_arriving_car
•	Car_ID: matching ‘people_ID’ from people_departing_car and people_arriving_car
•	Car_sample only carries people_sample when people_ID = Car_ID
•	When carrying people: 
	•	Speed (random) 20 to 70 (reload every 5 min)
	•	When arrives at destination: unload people*/

	species car_departing parent: car_sample{
		origin <- people_departing_car.origin with people_departing_car.ID = car_ID;
		destination <- /* the closest Parking to the same destination as people_departing_car.origin with people_departing_car.ID = car_ID */
	}
	species car_arriving parent:car_sample{
		origin <- /*One of the parkings associated to the Terminal to which people_arrivinv_car arrive*/
		destination <- people_arriving_car.destination with people_arriving_car.ID = car_ID;
		reflex wait /*when not carrying people*/
	}
}

...

	aspect base{
		draw cube (10) color: color;
	}	
}

species Bus_Shuttle {
	rgb color <- #pink;
/*
•	Carries people_sample with people_sample ‘mode’ = Bus_Shuttle ‘mode’
•	Carries people_sample with people_sample ‘Final_destination’ = Bus_Shuttle ‘Final_destination’
•	people max capacity: 55
•	people capacity: people max capacity – people loaded
•	Every 30 min:
	•	Load people_sample and luggage if people_sample ‘location’ = Bus Shuttle ‘location’
	•	When arrives at Destination: 
	•	unload all people_sample and lugagge
	•	change mode
	•	wait 15 min
•	Mode: Departure - carries people_taking_bus_with_luggage and people_droping_off_luggage_and_taking_bus
	•	Origin: ZOB
	•	Final_Destination: from Cruise Terminals when ‘Has_vessel = yes’
•	Mode: Arrival - carries people_arriving_bus
	•	Origin: Final_Destination in previous mode 
	•	Final_Destination: HBF
	•	Actual_Destination: ZOB (When the value Final_destination is HBF the Bus_Shuttle stops at ZOB, not at HBF)
*/

	...

	aspect base{
		draw cube (10) color: color;
	}	
}

species Sprinter {
	rgb color <- #purple;

/*
•	Max Number of Sprinters inside the boundary of Dropoffarea = 3
•	Mode: Departure
	•	Origin: Drop-off area HBF
	•	Destination: Origin in previous mode.
	•	Run every: Luggage capacity = 0 
	•	Lugagge max capacity: 55
	•	When arrives at Destination: unload Luggage and change mode
•	Mode: Arrival
	•	Origin_terminal (random): from Cruise Terminals when ‘Has_vessel = yes’
	•	Destination: Drop-off area HBF
	•	Run every: Luggage capacity = 0 
	•	Luggage max capacity: 55
	•	When arrives at Destination: unload Luggage and change mode
*/

	...

	aspect base{
		draw cube (10) color: color;
	}		
}

experiment city type: gui {
	/*Add parameters that we want to customize on every simulation*/
	parameter "parameter_here" var: variable_vame category: "Category_name" min: 0 max 10; /*Modify parameter here*/

	output{
		display map type: opentgl ambient_light: 150{
			species Buildings aspect:base;
			species HBF aspect:base;
			species Cruise_Terminals aspect:base;
			species Parking aspect:base;
			species ZOB aspect:base;
			species Dropoffarea aspect:base;
			species Venues aspect:base;
			species people_hamb aspect:base;
			species people_sample aspect:base;
			species Taxi aspect:base;
			species Car_hamb aspect:base;
			species Car_sample aspect:base;
			species Bus_shuttle aspect:base;
			species Sprinter aspect:base;
		}
	}
]
