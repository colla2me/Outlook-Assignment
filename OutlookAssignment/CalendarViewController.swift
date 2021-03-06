//
//  MyViewController.swift
//  TestingStackViewCells
//
//  Created by Robin Malhotra on 15/03/18.
//  Copyright © 2018 Robin Malhotra. All rights reserved.
//

import UIKit

class CalendarViewController: UIViewController, UITableViewDelegate, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, WeatherUpdatesDelegate {

	let eventDataProvider: EventDataProvider
	let locationWeatherProvider: LocationWeatherProvider

	//	#A week is always seven days
	//	Currently true, but historically false. A couple of out-of-use calendars, like the Decimal calendar and the Egyptian calendar had weeks that were 7, 8, or even 10 days.
	// http://yourcalendricalfallacyis.com
	let numberOfColumns: CGFloat = 7

	let generator = UIImpactFeedbackGenerator(style: .light)

	//mutating a `DateFormatter` is just as expensive as creating one, because changing the calendar, timezone, locale, or format causes new stuff to be loaded
	//the cost of `DateFormatter` comes from it loading up the formatting and region information from ICU
	let headerDateFormatter = DateFormatter()

	var indexPathOfHighlightedCell: IndexPath {
		didSet {
			if oldValue != indexPathOfHighlightedCell {
				collectionView.cellForItem(at: indexPathOfHighlightedCell)?.isHighlighted = true
				collectionView.cellForItem(at: oldValue)?.isHighlighted = false
				generator.impactOccurred()
			}
		}
	}

	let tableView = UITableView()
	let collectionView: UICollectionView
	let layout = UICollectionViewFlowLayout()

	enum ExpandedView {
		case agenda
		case calendar
	}

	var expandedState: ExpandedView = .agenda
	let eventSource = EventSource()

	let agendaDataSource: AgendaDataSource
	let calendarDataSource: CalendarDataSource

	init(dataProvider: EventDataProvider, session: URLSession = .shared, apiKey: String = Credentials.testCreds.apiKey) {
		self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
		// not sure if this is the best way to go to the middle
		self.indexPathOfHighlightedCell = IndexPath(row: 0, section: eventSource.offsets.count/2)

		self.agendaDataSource = AgendaDataSource(eventSource: eventSource)
		self.calendarDataSource = CalendarDataSource(eventSource: eventSource)

		self.eventDataProvider = dataProvider
		let forecastClient = ForecastAPIClient(session: session, key: apiKey)
		self.locationWeatherProvider = LocationWeatherProvider(forecastClient: forecastClient)
		super.init(nibName: nil, bundle: nil)
	}

	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		headerDateFormatter.dateStyle = .medium

		let (firstDate, lastDate) = eventSource.dateRange
		// Load data from provider and reload section
		eventDataProvider.loadEvents(from: firstDate, to: lastDate) { [weak self] (results) in
			guard let strongSelf = self else {
				return
			}
			strongSelf.eventSource.events = results.reduce([:], { (dict, arg) in
				let (date, events) = arg
				var copy = dict
				if let day = Day(from: date, calendar: strongSelf.eventSource.calendar) {
					copy[day] = events
				}
				return copy
			})
			let sectionsToReload = 0..<(strongSelf.eventSource.offsets.count)
			strongSelf.tableView.reloadSections(IndexSet(integersIn: sectionsToReload), with: .fade)
		}

		tableView.dataSource = agendaDataSource
		tableView.register(EventCell.self, forCellReuseIdentifier: "eventCell")
		tableView.register(EmptyEventsTableViewCell.self, forCellReuseIdentifier: "emptyEventsCell")
		tableView.register(DateHeaderView.self, forHeaderFooterViewReuseIdentifier: "header")
		tableView.delegate = self
		tableView.rowHeight = UITableViewAutomaticDimension
		tableView.sectionHeaderHeight = UITableViewAutomaticDimension
		tableView.tableFooterView = UIView()

		collectionView.dataSource = calendarDataSource
		collectionView.delegate = self
		collectionView.register(DayCell.self, forCellWithReuseIdentifier: "cell")
		collectionView.backgroundColor = .white

		view.backgroundColor = .white
		view.addSubview(tableView)
		view.addSubview(collectionView)

		layout.minimumInteritemSpacing = 0.0
		layout.minimumLineSpacing = 0.0

		locationWeatherProvider.delegate = self
		locationWeatherProvider.start()

		// scroll to offset:0 , i.e. today
		tableView.scrollToRow(at: IndexPath(row: 0, section: eventSource.offsets.count/2), at: .middle, animated: true)
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()

		let width = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right

		let numberOfRowsToShow: CGFloat = {
			switch expandedState {
			case .agenda:
				// when calendar is contracted - show 2 rows
				return 2
			case .calendar:
				// when calendar is expanded - show 5 rows
				return 5
			}
		}()

		collectionView.frame = CGRect(x: view.safeAreaInsets.left, y: view.safeAreaInsets.top, width: width, height: width / numberOfColumns * numberOfRowsToShow)
		tableView.frame = CGRect(x: collectionView.frame.minX, y: collectionView.frame.maxY, width: width, height: view.bounds.height - view.safeAreaInsets.top - collectionView.frame.height)
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		tableView.deselectRow(at: indexPath, animated: true)
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		guard let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as? DateHeaderView,
			let date = eventSource.dateFrom(offset: section) else {
				fatalError("Date beyond bounds of offsets")
		}
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .medium
		// need to highlight today with a blue highlight
		let isToday = eventSource.isDateSameDayAsToday(date)
		header.configure(title: headerDateFormatter.string(from: date), shouldHighlight: isToday)
		return header
	}

	func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
		if indexPathOfHighlightedCell == indexPath {
			cell.isHighlighted = true
		}
	}

	func scrollViewDidScroll(_ scrollView: UIScrollView) {

		if scrollView == tableView,
			let firstIndexPath = tableView.indexPathsForVisibleRows?.first,
			self.indexPathOfHighlightedCell != firstIndexPath {
			let collectionViewIndexPath = IndexPath(row: firstIndexPath.section, section: 0)
			collectionView.scrollToItem(at: collectionViewIndexPath, at: .bottom, animated: true)
			self.indexPathOfHighlightedCell = collectionViewIndexPath
		}
	}

	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		self.indexPathOfHighlightedCell = indexPath
		tableView.scrollToRow(at: IndexPath(row: 0, section: indexPath.row), at: .top, animated: true)
	}

	func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
		tableView.scrollToRow(at: IndexPath(row: 0, section: eventSource.offsets.count/2), at: .middle, animated: true)
		return false
	}

	func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		let oldState = self.expandedState
		if scrollView == collectionView {
			self.expandedState = .calendar
		} else if scrollView == tableView {
			self.expandedState = .agenda
		}

		guard oldState != expandedState else {
			return
		}
		self.view.setNeedsLayout()

		// https://developer.apple.com/documentation/uikit/uiview
		// Use of these methods is discouraged. Use the UIViewPropertyAnimator class to perform animations instead.
		let animator = UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
			self.view.layoutIfNeeded()
		}
		animator.startAnimation()
	}

	func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
		if indexPath.row % 7 == 0 {
			// Need to to do this because setting the cell width to _exactly_ 1/7th
			let leftOverWidth =  collectionView.bounds.width - floor(collectionView.frame.width/numberOfColumns) * 6
			let size = CGSize(width: leftOverWidth, height: floor(collectionView.frame.width/numberOfColumns))
			return size
		} else {
			let size = CGSize(width: floor(collectionView.frame.width/numberOfColumns), height: floor(collectionView.frame.width/numberOfColumns))
			return size
		}
	}

	func weatherDidUpdate(_ forecast: WeatherForecast) {
		self.navigationItem.title = "\(forecast.emojiRepresentation)  \(forecast.temperature.rounded())℉"
	}

}


