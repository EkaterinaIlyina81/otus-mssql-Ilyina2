/*
Домашнее задание по курсу MS SQL Server Developer в OTUS.

Занятие "03 - Подзапросы, CTE, временные таблицы".

Задания выполняются с использованием базы данных WideWorldImporters.

Бэкап БД можно скачать отсюда:
https://github.com/Microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0
Нужен WideWorldImporters-Full.bak

Описание WideWorldImporters от Microsoft:
* https://docs.microsoft.com/ru-ru/sql/samples/wide-world-importers-what-is
* https://docs.microsoft.com/ru-ru/sql/samples/wide-world-importers-oltp-database-catalog
*/

-- ---------------------------------------------------------------------------
-- Задание - написать выборки для получения указанных ниже данных.
-- Для всех заданий, где возможно, сделайте два варианта запросов:
--  1) через вложенный запрос
--  2) через WITH (для производных таблиц)
-- ---------------------------------------------------------------------------

USE WideWorldImporters

/*
1. Выберите сотрудников (Application.People), которые являются продажниками (IsSalesPerson), 
и не сделали ни одной продажи 04 июля 2015 года. 
Вывести ИД сотрудника и его полное имя. 
Продажи смотреть в таблице Sales.Invoices.
*/

Select distinct p.PersonID, p.FullName 
from Application.People AS p
JOIN Sales.Invoices si ON si.SalespersonPersonID = p.personID
where p.IsSalesperson = 1
AND NOT EXISTS (SELECT distinct p.PersonID, p.FullName, si.InvoiceDate, si.SalespersonPersonID, p.IsSalesperson
                  FROM Sales.Invoices si
                  WHERE si.SalespersonPersonID= p.personID
				  and si.InvoiceDate = '20150704'
				  				  )
order by p.PersonID

/*
2. Выберите товары с минимальной ценой (подзапросом). Сделайте два варианта подзапроса. 
Вывести: ИД товара, наименование товара, цена.
*/


	SELECT 
	ws.StockItemID, 
	ws.StockItemName, 
	ws. UnitPrice	
FROM Warehouse.StockItems ws
where ws.UnitPrice IN (SELECT MIN(UnitPrice) 
	FROM Warehouse.StockItems) 


	SELECT 
       ws.StockItemID, 
       ws.StockItemName, 
       ws.UnitPrice 
FROM (SELECT MIN(UnitPrice) as UnitPrice FROM Warehouse.StockItems) mp,
     Warehouse.StockItems ws
WHERE mp.UnitPrice = ws.UnitPrice

/*
3. Выберите информацию по клиентам, которые перевели компании пять максимальных платежей 
из Sales.CustomerTransactions. 
Представьте несколько способов (в том числе с CTE). 
*/


Select ct.CustomerID, c.CustomerName, ct.TransactionAmount
from Sales.CustomerTransactions ct
LEFT JOIN sales.Customers as c on c.CustomerID = ct.CustomerID 
where ct.TransactionAmount in (select top 5 ct2.TransactionAmount
                               from Sales.CustomerTransactions ct2
                               order by ct2.TransactionAmount desc)

;WITH CustomerCTE (CustomerID, TransactionAmount)
AS 
(select top 5 ct2.CustomerID,  ct2.TransactionAmount
                               from Sales.CustomerTransactions ct2
                               order by ct2.TransactionAmount desc)

Select t.CustomerID, c.CustomerName, t.TransactionAmount
from sales.Customers c
JOIN CustomerCTE t on t.CustomerID = c.CustomerID


/*
4. Выберите города (ид и название), в которые были доставлены товары, 
входящие в тройку самых дорогих товаров, а также имя сотрудника, 
который осуществлял упаковку заказов (PackedByPersonID).
*/


select ac.CityID, ac.CityName, ap.FullName
from sales.OrderLines sol,
     sales.Orders so, 
	 sales.Customers sc, 
	 Application.Cities ac, 
	 Sales.Invoices si, 
	 Application.People ap

where sol.OrderID = so.OrderID
and sc.CustomerID = so.CustomerID
and ac.CityID = sc.DeliveryCityID
and si.OrderID = so.OrderID
and ap.PersonID = si.PackedByPersonID
and sol.StockItemID in (select top 3 sol2.StockItemID
                          from (select sol3.StockItemID
                                     , max(sol3.UnitPrice) UnitPrice
                                from sales.OrderLines sol3
                                group by sol3.StockItemID
                               ) sol2
                          order by sol2.UnitPrice desc)
group by ac.CityID, ac.CityName, ap.FullName


;WITH UNITPRICECTE 
AS
(select top 3 sol2.StockItemID
                          from (select sol3.StockItemID
                                     , max(sol3.UnitPrice) UnitPrice
                                from sales.OrderLines sol3
                                group by sol3.StockItemID
                               ) sol2
                          order by sol2.UnitPrice desc)

Select ac.CityID, ac.CityName, ap.FullName
from sales.OrderLines sol
JOIN UNITPRICECTE as U on sol.StockItemID = u.StockItemID
JOIN sales.Orders as so on sol.OrderID = so.OrderID
JOIN sales.Customers as sc on sc.CustomerID = so.CustomerID
JOIN Application.Cities as ac on ac.CityID = sc.DeliveryCityID
JOIN Sales.Invoices as si on si.OrderID = so.OrderID
JOIN Application.People ap on ap.PersonID = si.PackedByPersonID

group by ac.CityID, ac.CityName, ap.FullName




-- ---------------------------------------------------------------------------
-- Опциональное задание
-- ---------------------------------------------------------------------------
-- Можно двигаться как в сторону улучшения читабельности запроса, 
-- так и в сторону упрощения плана\ускорения. 
-- Сравнить производительность запросов можно через SET STATISTICS IO, TIME ON. 
-- Если знакомы с планами запросов, то используйте их (тогда к решению также приложите планы). 
-- Напишите ваши рассуждения по поводу оптимизации. 

-- 5. Объясните, что делает и оптимизируйте запрос

SELECT 
	Invoices.InvoiceID, 
	Invoices.InvoiceDate,
	(SELECT People.FullName
		FROM Application.People
		WHERE People.PersonID = Invoices.SalespersonPersonID
	) AS SalesPersonName,
	SalesTotals.TotalSumm AS TotalSummByInvoice, 
	(SELECT SUM(OrderLines.PickedQuantity*OrderLines.UnitPrice)
		FROM Sales.OrderLines
		WHERE OrderLines.OrderId = (SELECT Orders.OrderId 
			FROM Sales.Orders
			WHERE Orders.PickingCompletedWhen IS NOT NULL	
				AND Orders.OrderId = Invoices.OrderId)	
	) AS TotalSummForPickedItems
FROM Sales.Invoices 
	JOIN
	(SELECT InvoiceId, SUM(Quantity*UnitPrice) AS TotalSumm
	FROM Sales.InvoiceLines
	GROUP BY InvoiceId
	HAVING SUM(Quantity*UnitPrice) > 27000) AS SalesTotals
		ON Invoices.InvoiceID = SalesTotals.InvoiceID
ORDER BY TotalSumm DESC

-- --

TODO: напишите здесь свое решение
