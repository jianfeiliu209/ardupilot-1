/// -*- tab-width: 4; Mode: C++; c-basic-offset: 4; indent-tabs-mode: nil -*-

void
control_nav_mixer()
{
	// control +- 45° is mixed with the navigation request by the Autopilot
	// output is in degrees = target pitch and roll of copter
	g.rc_1.servo_out = g.rc_1.control_mix(nav_roll);
	g.rc_2.servo_out = g.rc_2.control_mix(nav_pitch);
}

void
simple_mixer()
{
	// control +- 45° is mixed with the navigation request by the Autopilot
	// output is in degrees = target pitch and roll of copter
	g.rc_1.servo_out = nav_roll;
	g.rc_2.servo_out = nav_pitch;
}

void
limit_nav_pitch_roll(long pmax)
{
	// limit the nav pitch and roll of the copter
	//long pmax 	= g.pitch_max.get();
	nav_roll 	= constrain(nav_roll,  -pmax, pmax);
	nav_pitch 	= constrain(nav_pitch, -pmax, pmax);
}

void
output_stabilize_roll()
{
	float error;//, rate;
	//int dampener;

	error 		= g.rc_1.servo_out - dcm.roll_sensor;

	// limit the error we're feeding to the PID
	error 		= constrain(error, -2500, 2500);

	// write out angles back to servo out - this will be converted to PWM by RC_Channel
	g.rc_1.servo_out 	= g.pid_stabilize_roll.get_pi(error,  	delta_ms_fast_loop, 1.0);		// 2500 * .7 = 1750

	// We adjust the output by the rate of rotation:
	// Rate control through bias corrected gyro rates
	// omega is the raw gyro reading
	g.rc_1.servo_out	-= degrees(omega.x) * 100.0 * g.pid_stabilize_roll.kD();
	g.rc_1.servo_out	= min(g.rc_1.servo_out, 2500);
	g.rc_1.servo_out	= max(g.rc_1.servo_out, -2500);
}

void
output_stabilize_pitch()
{
	float error, rate;
	int dampener;

	error		= g.rc_2.servo_out - dcm.pitch_sensor;

	// limit the error we're feeding to the PID
	error		= constrain(error, -2500, 2500);

	// write out angles back to servo out - this will be converted to PWM by RC_Channel
	g.rc_2.servo_out 	= g.pid_stabilize_pitch.get_pi(error, 	delta_ms_fast_loop, 1.0);

	// We adjust the output by the rate of rotation:
	// Rate control through bias corrected gyro rates
	// omega is the raw gyro reading
	g.rc_2.servo_out	-= degrees(omega.y) * 100.0 * g.pid_stabilize_pitch.kD();
	g.rc_2.servo_out	= min(g.rc_2.servo_out, 2500);
	g.rc_2.servo_out	= max(g.rc_2.servo_out, -2500);
}

void
output_rate_roll()
{
	// rate control
	long rate		= degrees(omega.x) * 100; 												// 3rad = 17188 , 6rad = 34377
	rate			= constrain(rate, -36000, 36000);										// limit to something fun!
	long error		= ((long)g.rc_1.control_in * 8) - rate;									// control is += 4500 * 8 = 36000

	g.rc_1.servo_out 	= g.pid_acro_rate_roll.get_pid(error, delta_ms_fast_loop, 1.0); 	// .075 * 36000 = 2700
	g.rc_1.servo_out 	= constrain(g.rc_1.servo_out, -2400, 2400);							// limit to 2400
}

void
output_rate_pitch()
{
	// rate control
	long rate		= degrees(omega.y) * 100; 												// 3rad = 17188 , 6rad = 34377
	rate			= constrain(rate, -36000, 36000);										// limit to something fun!
	long error		= ((long)g.rc_2.control_in * 8) - rate;									// control is += 4500 * 8 = 36000

	g.rc_2.servo_out 	= g.pid_acro_rate_pitch.get_pid(error, delta_ms_fast_loop, 1.0); 	// .075 * 36000 = 2700
	g.rc_2.servo_out 	= constrain(g.rc_2.servo_out, -2400, 2400);							// limit to 2400
}

// Zeros out navigation Integrators if we are changing mode, have passed a waypoint, etc.
// Keeps outdated data out of our calculations
void
reset_I(void)
{
	// I removed these, they don't seem to be needed.
}


/*************************************************************
throttle control
****************************************************************/

// user input:
// -----------
void output_manual_throttle()
{
	g.rc_3.servo_out = (float)g.rc_3.control_in * angle_boost();
}

// Autopilot
// ---------
void output_auto_throttle()
{
	g.rc_3.servo_out 	= (float)nav_throttle * angle_boost();
	// make sure we never send a 0 throttle that will cut the motors
	g.rc_3.servo_out = max(g.rc_3.servo_out, 1);
}

void calc_nav_throttle()
{
	// limit error
	long error = constrain(altitude_error, -400, 400);
	float scaler = 1.0;

	if(error < 0){
		// try and prevent rapid fall
		//scaler = (altitude_sensor == BARO) ? 1 : 1;
	}

	if(altitude_sensor == BARO){
		nav_throttle = g.pid_baro_throttle.get_pid(error, dTnav2, scaler);	// .25
		nav_throttle = g.throttle_cruise + constrain(nav_throttle, -35, 80);
	}else{
		nav_throttle = g.pid_sonar_throttle.get_pid(error, dTnav2, scaler);	// .5
		nav_throttle = g.throttle_cruise + constrain(nav_throttle, -70, 150);
	}

	// simple filtering
	nav_throttle 		= (nav_throttle + nav_throttle_old) >> 1;
	nav_throttle_old 	= nav_throttle;

	// clear the new data flag
	invalid_throttle = false;

	//Serial.printf("nav_thr %d, scaler %2.2f ", nav_throttle, scaler);
}

float angle_boost()
{
	float temp = cos_pitch_x * cos_roll_x;
	temp = 2.0 - constrain(temp, .5, 1.0);
	return temp;
}

/*************************************************************
yaw control
****************************************************************/

void output_manual_yaw()
{
	if(g.rc_3.control_in == 0){
		// we want to only call this once
		if(did_clear_yaw_control == false){
			clear_yaw_control();
			did_clear_yaw_control = true;
		}

	}else{ // motors running

		// Yaw control
		if(g.rc_4.control_in == 0){
			output_yaw_with_hold(true); // hold yaw
		}else{
			output_yaw_with_hold(false); // rate control yaw
		}

		did_clear_yaw_control = false;
	}
}

void auto_yaw()
{
	output_yaw_with_hold(true); // hold yaw
}

void
clear_yaw_control()
{
	//Serial.print("Clear ");
	rate_yaw_flag  		= false;			// exit rate_yaw_flag
	nav_yaw 			= dcm.yaw_sensor;	// save our Yaw
	g.rc_4.servo_out 	= 0;				// reset our output. It can stick when we are at 0 throttle
	yaw_error 			= 0;
	yaw_debug 			= YAW_HOLD; 		//0
}

#if YAW_OPTION == 0
void
output_yaw_with_hold(boolean hold)
{
	// rate control
	long rate		= degrees(omega.z) * 100; 											// 3rad = 17188 , 6rad = 34377
	rate			= constrain(rate, -36000, 36000);									// limit to something fun!
	int dampener 	= rate * g.pid_yaw.kD();											// 34377 * .175 = 6000

	if(hold){
		// look to see if we have exited rate control properly - ie stopped turning
		if(rate_yaw_flag){
			// we are still in motion from rate control
			if(fabs(omega.z) < .4){
				clear_yaw_control();
				hold = true;			// just to be explicit
				//Serial.print("C");
			}else{
				hold = false;			// return to rate control until we slow down.
				//Serial.print("D");
			}
		}

	}else{
		// rate control

		// this indicates we are under rate control, when we enter Yaw Hold and
		// return to 0° per second, we exit rate control and hold the current Yaw
		rate_yaw_flag 	= true;
		yaw_error 		= 0;
	}

	if(hold){
		// try and hold the current nav_yaw setting
		yaw_error				= nav_yaw - dcm.yaw_sensor; 									// +- 60°
		yaw_error 				= wrap_180(yaw_error);

		// limit the error we're feeding to the PID
		yaw_error				= constrain(yaw_error,	 -4000, 4000);						// limit error to 60 degees

		// Apply PID and save the new angle back to RC_Channel
		g.rc_4.servo_out 		= g.pid_yaw.get_pi(yaw_error, delta_ms_fast_loop, 1.0); 		// .4 * 4000 = 1600

		// add in yaw dampener
		g.rc_4.servo_out		-= constrain(dampener, -1600, 1600);
		yaw_debug 				= YAW_HOLD; //0

	}else{

		if(g.rc_4.control_in == 0){

			// adaptive braking
			g.rc_4.servo_out 	= (int)(-800.0 * omega.z);

			yaw_debug 			= YAW_BRAKE;  // 1

		}else{
			// RATE control
																// Hein, 5/21/11
			long error			= ((long)g.rc_4.control_in * 6) - (rate * 2);					// control is += 6000 * 6 = 36000
			g.rc_4.servo_out 	= g.pid_acro_rate_yaw.get_pid(error, delta_ms_fast_loop, 1.0);	// kP .07 * 36000 = 2520
			yaw_debug 			= YAW_RATE;  // 2
		}
	}

	// Limit Output
	g.rc_4.servo_out 	= constrain(g.rc_4.servo_out, -2400, 2400);								// limit to 24°

	//Serial.printf("%d\n",g.rc_4.servo_out);
}
#elif YAW_OPTION == 1

void
output_yaw_with_hold(boolean hold)
{
	// re-define nav_yaw if we have stick input
	if(g.rc_4.control_in != 0){
		// set nav_yaw + or - the current location
		nav_yaw 	= (long)g.rc_4.control_in + dcm.yaw_sensor;
	}

	// we need to wrap our value so we can be 0 to 360 (*100)
	nav_yaw 	= wrap_360(nav_yaw);

	// how far off is nav_yaw from our current yaw?
	yaw_error 	= nav_yaw - dcm.yaw_sensor;

	// we need to wrap our value so we can be -180 to 180 (*100)
	yaw_error 	= wrap_180(yaw_error);

	// limit the error we're feeding to the PID
	yaw_error				= constrain(yaw_error,	 -3500, 3500);						// limit error to 60 degees

	// Apply PID and save the new angle back to RC_Channel
	g.rc_4.servo_out 		= g.pid_yaw.get_pi(yaw_error, delta_ms_fast_loop, 1.0); 		// .4 * 4000 = 1600

	// add in yaw dampener
	g.rc_4.servo_out		-= degrees(omega.z) * 100 * g.pid_yaw.kD();
	yaw_error				= constrain(yaw_error,	 -2500, 2500);						// limit error to 60 degees
}
#endif
