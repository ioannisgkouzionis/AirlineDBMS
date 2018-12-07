package src;
import java.awt.event.ComponentAdapter;


import java.awt.event.ComponentEvent;
import javax.swing.JDialog;
import javax.swing.JOptionPane;
import javax.swing.JPasswordField;
import javax.swing.SwingUtilities;

import tuc.eced.cs201.io.*;

import java.sql.*;

import java.util.Date;

public  class DB_administrate {
	/* Dimiourgisame ton enumerated typo action prokeimenou na ginei agora/kratisi eisitiriou */
	public  enum action {
	    action1 ("buy"),
	    action2 ("reserve");


	    public final String name;       

	    private action(String s) {
	        name = s;
	    }

	    public boolean equalsName(String otherName){
	        return (otherName == null)? false:name.equals(otherName);
	    }

	    public String toString(){
	       return name;
	    }

	}

////////////////////////////
		Connection conn;
		StandardInputRead sir;

		
		public DB_administrate() {
			try {
	     		Class.forName("org.postgresql.Driver");
	     		conn = DriverManager.getConnection("jdbc:postgresql://localhost:5432/Project2_Final","postgres",getPassword());
	     		
	     		conn.setAutoCommit(false);
				conn.setTransactionIsolation(Connection.TRANSACTION_SERIALIZABLE);
			} catch(Exception e) {
	            e.printStackTrace();
			}
			sir = new StandardInputRead();
		}

			/* Dimiourgia methodou gia anazitisi/emfanisi ptisewn vasei tou aerodromiou proorismou */
			public void search_Flight(java.sql.Date dat, String dest) throws SQLException {
			PreparedStatement pst 
	        = conn.prepareStatement("SELECT gfd.fschedule_id,gfd.aircraft_code,gfd.fdate," +
	        						" gfd.fprogram_id,gfd.flight_code,gfd.dep_shrt,gfd.dest_shrt," +
	        						" gfd.dep_time,gfd.arr_time,gfd.price" +
	        						" from get_flight_details gfd where  dest_shrt=? " +
	        						" and fdate=?");
			pst.setString(1,dest);
			pst.setDate(2, (java.sql.Date) dat);

			ResultSet rs = pst.executeQuery();
			System.out.println("--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ");
			System.out.println("Flight Schedule ID		Aircraft code		Flight Date		Flight Program ID		Flight Code		Departure		Destination		Departure Time		Arrival Time		Price");
			while (rs.next()) {
				
				System.out.println("\t"+rs.getString(1)+	
						"\t\t\t"+     rs.getString(2)+	
						"\t\t\t"+	  rs.getString(3)+		
						"\t\t\t"+	  rs.getString(4)+	
						"\t\t\t"+	  rs.getString(5)+		
						"\t\t\t"+	  rs.getString(6)+
						"\t\t\t"+     rs.getString(7)+
						"\t\t\t"+     rs.getString(8)+
						"\t\t"+     rs.getString(9)+
						"\t\t"+     rs.getString(10));
				
			}
			System.out.println("--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- ");
		}

		/* Dimiourgia methodou gia emfanisi twn kratisewn gia kapoia ptisi */
		public void show_Reservation(int fs_id) throws SQLException
		{
			PreparedStatement pst 
	        = conn.prepareStatement("select gtd.fschedule_id,gtd.t_id,gtd.t_date," +
	        		"gtd.c_id,gtd.action from get_trans_details gtd where gtd.fschedule_id=? and gtd.action='reserve'");	
				
			pst.setInt(1, fs_id);
			ResultSet rs = pst.executeQuery();
			System.out.println("-----------------------------------------------------------------------------------------------------------------------");
			System.out.println("Flight Schedule ID	Transaction ID		Transaction Date		Customer ID			Action");
			while (rs.next()) {
				
				System.out.println(""+rs.getString(1)+	
						"\t  \t\t"+rs.getString(2)+	
						"\t  \t\t"+	rs.getString(3)+		
						"\t  \t\t"+	rs.getString(4)+	
						"\t  \t\t"+	rs.getString(5));
			}
			System.out.println("-----------------------------------------------------------------------------------------------------------------------");
			
		}	
		
		/* Dimiourgia methodou gia agora kai kratisi eisitiriou gia kapoia ptisi */
		public void Reserve_Or_Buy(int fs_id,int cust_id,	String act  , int gs_id) throws SQLException
		{
			CallableStatement cst =conn.prepareCall("select insert_gstaff_transaction(?,?,?::action,?)");
			cst.setInt(1,fs_id);
			cst.setInt(2, cust_id);			
			cst.setString(3,act);
			cst.setInt(4,gs_id);
			cst.executeQuery();
			System.out.println("You succesfully ordered ticket .To complete transaction press 2");
			cst.close();
		}
		
		/* Dimiourgia tou menu emfanisis twn epilogwn tou xristi */		
		public void menu() {
			int code = 0;
			
				
			while(true) {
				System.out.println("DATABASE MENU"); 
				System.out.println("1.Abort Transaction");
				System.out.println("2.Commit Transaction");
				System.out.println("3.Search Flight");
				System.out.println("4.Buy/Reserve Tickets");
				System.out.println("5.Show Reservations");				
				System.out.println("6.Exit");
				int choice = sir.readPositiveInt("Enter choice:");
				
				try {
					switch (choice) {
							case 1: conn.rollback(); break;
							/////////////////////////////////////////////////////////////////////////////////////
							case 2: conn.commit(); break;
							/////////////////////////////////////////////////////////////////////////////////////
							case 3:
			     	 			Date d = (Date) sir.readDate("Give date to search flight: ");
			     	 			java.sql.Date sql_d = new java.sql.Date(d.getTime());
			     	 			String shrt = sir.readString("Give destination to search flight:");
			     	 			search_Flight(sql_d,shrt);
			     	 				break;
			     	 		
			     	 		/////////////////////////////////////////////////////////////////////////////////////
			     	 		case 4: 
			     	 		int fs_id=sir.readPositiveInt("Please give flightschedule id to reserve or buy ticker for flight:");
			     	 		int cust_id=sir.readPositiveInt("Please give customer id to reserve or buy ticker for flight:");
			     	 		String ac=sir.readString("Select reserve or buy for your transaction:");
			     	 		if (!(ac.equals("reserve")) && !(ac.equals("buy")))
			     	 		{
			     	 			do {
				     	 			ac=sir.readString("Give again action:");
				     	 		}while(!(ac.equals("reserve")) && !(ac.equals("buy")));
				     	 	}
			     	 		     	 	
			     	 		int gs_id=sir.readPositiveInt("Please give gstaff id to reserve or buy ticket for flight:");			     	 		
			     	 		//action act = new action(ac);
			     	 		Reserve_Or_Buy(fs_id,cust_id,ac,gs_id);
			     	 				
			     	 		break;
			     	 		
			     	 		
			     	 		/////////////////////////////////////////////////////////////////////////////////////
			     	 		case 5: 
			     	 			int fsc_id=sir.readPositiveInt("Give flight schedule id to check reservation:");
			     	 			show_Reservation(fsc_id);
			     	 			break;		     	 		
			     	 		
			     	 		
			     	 		case 6: System.exit(0); break;
			     	 		default:System.out.println("Wrong choice! Try again:");
					}
				} catch (SQLException ex) {
					System.out.println("Error Message = "+ex.getMessage());
					System.out.println("Error occured in SQL execution. Errno = "+ex.getSQLState());
					System.out.println("Operation Failed ....");
				}
			}
			
			
		}

		/**
		 * @param args
		 */
		public static void main(String[] args) {
			
			DB_administrate db = new DB_administrate();
			db.menu();
		}
		
		public String getPassword(){
			final JPasswordField jpf = new JPasswordField();
			JOptionPane jop = new JOptionPane(jpf, JOptionPane.QUESTION_MESSAGE,
			        JOptionPane.OK_CANCEL_OPTION);
			JDialog dialog = jop.createDialog("Password:");
			dialog.addComponentListener(new ComponentAdapter() {
			    @Override
			    public void componentShown(ComponentEvent e) {
			        SwingUtilities.invokeLater(new Runnable() {
			            @Override
			            public void run() {
			                jpf.requestFocusInWindow();
			            }
			        });
			    }
			});
			dialog.setVisible(true);
			int result = (Integer) jop.getValue();
			dialog.dispose();
			char[] password = null;
			if (result == JOptionPane.OK_OPTION) {
			    password = jpf.getPassword();
			}
			return new String(password);
		}
		

	}



